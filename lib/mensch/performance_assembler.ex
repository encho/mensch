defmodule Mensch.PerformanceAssembler do
  @moduledoc """
  Assembles playable `%Mensch.Performance{}` timelines from sample data.

  This module does not own seed/sample data. It consumes sample definitions
  provided by `Mensch.SampleDb`, renders each entry through its configured
  machine, aligns entries on the global timeline, merges frames, and performs
  a final MPE channel allocation pass.
  """

  alias Mensch.ChordSpec
  alias Mensch.BeatPosition
  alias Mensch.Machine
  alias Mensch.Machine.MachineFrameSequence
  alias Mensch.Midi.Connection
  alias Mensch.Performance
  alias Mensch.SampleDb
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @doc "Assembles the default sample-1 entry set from `Mensch.SampleDb`."
  @spec generate_sample() :: Performance.t()
  def generate_sample do
    generate_sample(SampleDb.default_sample_entries(), SampleDb.default_sample_context())
  end

  @doc "Assembles and aggregates a full sample timeline from entry maps."
  @spec generate_sample([map()], SampleContext.t()) :: Performance.t()
  def generate_sample(entries, %SampleContext{} = sample_context) when is_list(entries) do
    sample_context = SampleContext.validate!(sample_context)

    entries
    |> Enum.with_index()
    |> Enum.map(fn {%{chord_spec: chord_spec, timeline_context: timeline_context} = entry,
                    entry_index} ->
      machine = Map.fetch!(entry, :machine)

      entry
      |> render_entry(
        chord_spec,
        timeline_context,
        machine,
        sample_context,
        entry_index
      )
    end)
    |> build_global_performance(sample_context)
    |> rechannelize_performance()
  end

  @doc "Returns sample-1 entries from `Mensch.SampleDb`."
  @spec default_sample_entries() :: [map()]
  def default_sample_entries, do: SampleDb.default_sample_entries()

  @doc "Returns the full sample catalog from `Mensch.SampleDb`."
  @spec default_samples() :: [map()]
  def default_samples, do: SampleDb.default_samples()

  @doc "Renders a chord spec via a machine instance implementing `Mensch.Machine`."
  @spec generate(ChordSpec.t(), SampleContext.t(), TimelineContext.t(), struct()) ::
          Performance.t()
  def generate(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        machine
      ) do
    sample_context = SampleContext.validate!(sample_context)
    start_mbeat = TimelineContext.start_mbeat(timeline_context, sample_context)

    local_timeline_context = %TimelineContext{
      start_beat: BeatPosition.new(0, 0, 0),
      duration_mbeats: timeline_context.duration_mbeats
    }

    machine_opts = [entry_start_mbeat_abs: start_mbeat]

    chord_spec
    |> then(
      &Machine.build_frame_sequence(
        machine,
        &1,
        sample_context,
        local_timeline_context,
        machine_opts
      )
    )
    |> shift_entry(start_mbeat)
    |> to_global_performance(sample_context)
    |> rechannelize_performance()
  end

  @doc "The note name and octave for a MIDI note number, e.g. `64` -> `{:e, 4}`."
  @spec note_name(integer()) :: {ChordSpec.root(), integer()}
  def note_name(note_number), do: ChordSpec.note_name(note_number)

  defp render_entry(
         _entry,
         %ChordSpec{} = chord_spec,
         %TimelineContext{} = timeline_context,
         machine,
         %SampleContext{} = sample_context,
         entry_index
       )
       when is_integer(entry_index) do
    start_mbeat = TimelineContext.start_mbeat(timeline_context, sample_context)

    local_timeline_context = %TimelineContext{
      start_beat: BeatPosition.new(0, 0, 0),
      duration_mbeats: timeline_context.duration_mbeats
    }

    machine_opts = [
      entry_start_mbeat_abs: start_mbeat
    ]

    local_entry =
      chord_spec
      |> then(
        &Machine.build_frame_sequence(
          machine,
          &1,
          sample_context,
          local_timeline_context,
          machine_opts
        )
      )
      |> tag_sample_entry_index(entry_index)

    shift_entry(local_entry, start_mbeat)
  end

  defp shift_entry(%MachineFrameSequence{} = rendered_entry, start_mbeat) do
    shifted_frames =
      Enum.map(rendered_entry.frames, fn frame ->
        local_mbeat = Map.get(frame, :at_mbeat, 0)
        %{frame | at_mbeat: local_mbeat + start_mbeat}
      end)

    %MachineFrameSequence{rendered_entry | frames: shifted_frames}
  end

  defp tag_sample_entry_index(%MachineFrameSequence{} = rendered_entry, entry_index) do
    tagged_frames =
      Enum.map(rendered_entry.frames, fn frame ->
        tagged_notes =
          Enum.map(frame.notes, fn note ->
            Map.put(note, :sample_entry_index, entry_index)
          end)

        %{frame | notes: tagged_notes}
      end)

    %MachineFrameSequence{rendered_entry | frames: tagged_frames}
  end

  defp build_global_performance(rendered_entries, %SampleContext{} = sample_context)
       when is_list(rendered_entries) do
    merged_frames =
      rendered_entries
      |> Enum.flat_map(& &1.frames)
      |> Enum.group_by(&Map.get(&1, :at_mbeat, 0))
      |> Enum.map(fn {at_mbeat, frames} ->
        %{
          at_mbeat: at_mbeat,
          at_ms: SampleContext.mbeats_to_ms(sample_context, at_mbeat),
          notes: Enum.flat_map(frames, & &1.notes)
        }
      end)
      |> Enum.sort_by(& &1.at_mbeat)

    to_global_performance(
      %MachineFrameSequence{frames: merged_frames},
      sample_context
    )
  end

  defp to_global_performance(
         %MachineFrameSequence{} = rendered_entry,
         %SampleContext{} = sample_context
       ) do
    duration_mbeats = duration_mbeats_from_frames(rendered_entry.frames)

    %Performance{
      bpm: sample_context.bpm,
      time_signature: sample_context.time_signature,
      granularity_ms:
        SampleContext.mbeats_to_ms(sample_context, SampleContext.frame_units(sample_context)),
      duration_ms: SampleContext.mbeats_to_ms(sample_context, duration_mbeats),
      frames: rendered_entry.frames
    }
  end

  defp duration_mbeats_from_frames(frames) when is_list(frames) do
    frames
    |> List.last()
    |> then(&if(&1, do: &1.at_mbeat, else: 0))
  end

  defp rechannelize_performance(%Performance{} = performance) do
    channels = Connection.member_channels()
    channel_fallback = List.first(channels, 1)
    assigned_channels = assign_channels_by_note(performance.frames, channels, channel_fallback)

    frames =
      Enum.map(performance.frames, fn frame ->
        remapped_notes =
          Enum.map(frame.notes, fn note ->
            note_id = logical_note_id(note)
            %{note | channel: Map.get(assigned_channels, note_id, channel_fallback)}
          end)

        %{frame | notes: remapped_notes}
      end)

    %Performance{performance | frames: frames}
  end

  defp assign_channels_by_note(frames, channels, channel_fallback) do
    {_, assigned_channels} =
      Enum.reduce(frames, {%{active_by_channel: %{}, assigned_by_note: %{}}, %{}}, fn frame,
                                                                                      {state,
                                                                                       assigned} ->
        Enum.reduce(frame.notes, {state, assigned}, fn note, {acc, acc_assigned} ->
          note_id = logical_note_id(note)

          {channel, acc} =
            cond do
              note.note_on and not Map.has_key?(acc.assigned_by_note, note_id) ->
                allocate_note_channel(acc, note_id, channels, channel_fallback)

              Map.has_key?(acc.assigned_by_note, note_id) ->
                {Map.fetch!(acc.assigned_by_note, note_id), acc}

              true ->
                {channel_fallback, acc}
            end

          acc =
            if note.note_off and Map.get(acc.assigned_by_note, note_id) == channel do
              release_note_channel(acc, channel)
            else
              acc
            end

          {acc, Map.put(acc_assigned, note_id, channel)}
        end)
      end)

    assigned_channels
  end

  defp allocate_note_channel(state, note_id, channels, channel_fallback) do
    channel =
      Enum.find(channels, fn candidate -> not Map.has_key?(state.active_by_channel, candidate) end) ||
        channel_fallback

    next_state =
      state
      |> put_in([:assigned_by_note, note_id], channel)
      |> put_in([:active_by_channel, channel], note_id)

    {channel, next_state}
  end

  defp release_note_channel(state, channel) do
    update_in(state, [:active_by_channel], &Map.delete(&1, channel))
  end

  defp logical_note_id(note) do
    {
      Map.get(note, :sample_entry_index, -1),
      Map.get(note, :machine_id, :unknown),
      Map.get(note, :chord_instance_id, 0),
      Map.get(note, :event_index, 0),
      note.note
    }
  end
end
