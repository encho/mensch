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
    entries
    |> Enum.with_index()
    |> Enum.map(fn {%{chord_spec: chord_spec, timeline_context: timeline_context} = entry,
                    entry_index} ->
      machine = Map.fetch!(entry, :machine)

      entry
      |> render_entry_performance(
        chord_spec,
        timeline_context,
        machine,
        sample_context,
        entry_index
      )
    end)
    |> merge_performances(sample_context)
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
    machine_opts = machine_timing_opts(sample_context, timeline_context)

    Machine.render(machine, chord_spec, sample_context, timeline_context, machine_opts)
    |> rechannelize_performance()
  end

  @doc "The note name and octave for a MIDI note number, e.g. `64` -> `{:e, 4}`."
  @spec note_name(integer()) :: {ChordSpec.root(), integer()}
  def note_name(note_number), do: ChordSpec.note_name(note_number)

  defp render_entry_performance(
         _entry,
         %ChordSpec{} = chord_spec,
         %TimelineContext{} = timeline_context,
         machine,
         %SampleContext{} = sample_context,
         entry_index
       )
       when is_integer(entry_index) do
    start_tick = TimelineContext.start_tick(timeline_context, sample_context)

    local_timeline_context = %TimelineContext{
      start_beat: BeatPosition.new(0, 0, 0),
      duration_mbeats: timeline_context.duration_mbeats
    }

    machine_opts = [
      entry_start_tick_abs: start_tick,
      ticks_per_beat: SampleContext.ticks_per_beat(sample_context)
    ]

    local_performance =
      chord_spec
      |> then(&Machine.render(machine, &1, sample_context, local_timeline_context, machine_opts))
      |> tag_sample_entry_index(entry_index)

    shift_performance(local_performance, start_tick, sample_context)
  end

  defp machine_timing_opts(sample_context, timeline_context) do
    [
      entry_start_tick_abs: TimelineContext.start_tick(timeline_context, sample_context),
      ticks_per_beat: SampleContext.ticks_per_beat(sample_context)
    ]
  end

  defp shift_performance(
         %Performance{} = performance,
         start_tick,
         %SampleContext{} = sample_context
       ) do
    shifted_music =
      Enum.map(performance.music, fn frame ->
        shifted_tick = frame.at_tick + start_tick

        %{
          at_tick: shifted_tick,
          at_ms: SampleContext.ticks_to_ms(sample_context, shifted_tick),
          notes: frame.notes
        }
      end)

    last_tick = shifted_music |> List.last() |> then(&if(&1, do: &1.at_tick, else: 0))

    %Performance{
      performance
      | duration_ms: SampleContext.ticks_to_ms(sample_context, last_tick),
        music: shifted_music
    }
  end

  defp tag_sample_entry_index(%Performance{} = performance, entry_index) do
    tagged_music =
      Enum.map(performance.music, fn frame ->
        tagged_notes =
          Enum.map(frame.notes, fn note ->
            Map.put(note, :sample_entry_index, entry_index)
          end)

        %{frame | notes: tagged_notes}
      end)

    %Performance{performance | music: tagged_music}
  end

  defp merge_performances([], %SampleContext{} = sample_context) do
    %Performance{
      bpm: sample_context.bpm,
      time_signature: sample_context.time_signature,
      granularity_ms:
        SampleContext.ticks_to_ms(sample_context, SampleContext.frame_ticks(sample_context)),
      duration_ms: 0,
      music: []
    }
  end

  defp merge_performances(performances, %SampleContext{} = sample_context) do
    merged_music =
      performances
      |> Enum.flat_map(& &1.music)
      |> Enum.group_by(& &1.at_tick)
      |> Enum.map(fn {at_tick, frames} ->
        %{
          at_tick: at_tick,
          at_ms: SampleContext.ticks_to_ms(sample_context, at_tick),
          notes: Enum.flat_map(frames, & &1.notes)
        }
      end)
      |> Enum.sort_by(& &1.at_tick)

    %Performance{
      bpm: sample_context.bpm,
      time_signature: sample_context.time_signature,
      granularity_ms: performances |> Enum.map(& &1.granularity_ms) |> Enum.min(),
      duration_ms: performances |> Enum.map(& &1.duration_ms) |> Enum.max(),
      music: merged_music
    }
  end

  defp rechannelize_performance(%Performance{} = performance) do
    channels = Connection.member_channels()
    channel_fallback = List.first(channels, 1)
    assigned_channels = assign_channels_by_note(performance.music, channels, channel_fallback)

    music =
      Enum.map(performance.music, fn frame ->
        remapped_notes =
          Enum.map(frame.notes, fn note ->
            note_id = logical_note_id(note)
            %{note | channel: Map.get(assigned_channels, note_id, channel_fallback)}
          end)

        %{frame | notes: remapped_notes}
      end)

    %Performance{performance | music: music}
  end

  defp assign_channels_by_note(music, channels, channel_fallback) do
    {_, assigned_channels} =
      Enum.reduce(music, {%{active_by_channel: %{}, assigned_by_note: %{}}, %{}}, fn frame,
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
