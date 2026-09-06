defmodule Mensch.Render do
  @moduledoc """
  Facade that renders a performance via a concrete `Mensch.Machine`.

  Use `generate_sample/0` or `generate_sample/2` to render and aggregate a
  full multi-entry sample timeline.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machines.RootModulated
  alias Mensch.Machines.StrummedMpe
  alias Mensch.Midi.Connection
  alias Mensch.Performance
  alias Mensch.SampleContext
  alias Mensch.TimelineContext
  alias Mensch.BeatPosition

  @default_sample_context %SampleContext{bpm: 120, time_signature: {4, 4}, ppq: 96}
  @default_timeline_context %TimelineContext{
    start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
    duration_ticks: 384
  }

  @default_sample_entries [
    %{
      chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
        duration_ticks: 768
      },
      machine_module: StrummedMpe
    },
    %{
      chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 1, beat: 3, tick: 0},
        duration_ticks: 480
      },
      machine_module: StrummedMpe
    },
    %{
      chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 3, beat: 0, tick: 0},
        duration_ticks: 384
      },
      machine_module: StrummedMpe
    }
  ]

  @default_sample_two_context %SampleContext{bpm: 80, time_signature: {4, 4}, ppq: 96}
  @default_sample_two_entries [
    %{
      chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
        duration_ticks: 1536
      },
      machine_module: StrummedMpe
    }
  ]

  @default_sample_three_context @default_sample_context
  @default_sample_three_entries [
    %{
      chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
        duration_ticks: 768
      },
      machine_module: RootModulated
    },
    %{
      chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 1, beat: 3, tick: 0},
        duration_ticks: 480
      },
      machine_module: RootModulated
    },
    %{
      chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 3, beat: 0, tick: 0},
        duration_ticks: 384
      },
      machine_module: RootModulated
    }
  ]

  @default_samples [
    %{
      id: "sample-1",
      name: "Sample 1 · Dm7 G7 Cmaj7",
      sample_context: @default_sample_context,
      sample_entries: @default_sample_entries
    },
    %{
      id: "sample-2",
      name: "Sample 2 · Cmaj7 Drone",
      sample_context: @default_sample_two_context,
      sample_entries: @default_sample_two_entries
    },
    %{
      id: "sample-3",
      name: "Sample 3 · Dm7 G7 Cmaj7 Root",
      sample_context: @default_sample_three_context,
      sample_entries: @default_sample_three_entries
    }
  ]

  @doc "Default multi-entry sample render (aggregated timeline)."
  @spec generate_sample() :: Performance.t()
  def generate_sample do
    generate_sample(@default_sample_entries, @default_sample_context)
  end

  @doc "Renders and aggregates a full sample timeline from entry maps."
  @spec generate_sample([map()], SampleContext.t()) :: Performance.t()
  def generate_sample(entries, %SampleContext{} = sample_context) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.map(fn {%{chord_spec: chord_spec, timeline_context: timeline_context} = entry,
                    entry_index} ->
      machine_module = Map.get(entry, :machine_module, StrummedMpe)

      entry
      |> render_entry_performance(
        chord_spec,
        timeline_context,
        machine_module,
        sample_context,
        entry_index
      )
    end)
    |> merge_performances(sample_context)
    |> rechannelize_performance()
  end

  @doc "Returns the default sample entries for UI/debug display."
  @spec default_sample_entries() :: [map()]
  def default_sample_entries, do: @default_sample_entries

  @doc "Returns the default sample catalog for UI selection."
  @spec default_samples() :: [map()]
  def default_samples, do: @default_samples

  @doc "Returns the default sample context used by `generate_sample/0`."
  @spec default_sample_context() :: SampleContext.t()
  def default_sample_context, do: @default_sample_context

  @doc "Renders the given chord spec using default sample/timeline contexts."
  @spec generate(ChordSpec.t()) :: Performance.t()
  def generate(%ChordSpec{} = chord_spec) do
    StrummedMpe.render(chord_spec, @default_sample_context, @default_timeline_context)
    |> rechannelize_performance()
  end

  @doc "Renders a chord spec with an explicit sample/timeline context via the default machine."
  @spec generate(ChordSpec.t(), SampleContext.t(), TimelineContext.t()) :: Performance.t()
  def generate(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context
      ) do
    StrummedMpe.render(chord_spec, sample_context, timeline_context)
    |> rechannelize_performance()
  end

  @doc "Renders a chord spec via a specific machine module implementing `Mensch.Machine`."
  @spec generate(ChordSpec.t(), SampleContext.t(), TimelineContext.t(), module()) ::
          Performance.t()
  def generate(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        machine_module
      )
      when is_atom(machine_module) do
    machine_module.render(chord_spec, sample_context, timeline_context)
    |> rechannelize_performance()
  end

  @doc "The note name and octave for a MIDI note number, e.g. `64` -> `{:e, 4}`."
  @spec note_name(integer()) :: {ChordSpec.root(), integer()}
  def note_name(note_number), do: ChordSpec.note_name(note_number)

  defp render_entry_performance(
         _entry,
         %ChordSpec{} = chord_spec,
         %TimelineContext{} = timeline_context,
         machine_module,
         %SampleContext{} = sample_context,
         entry_index
       )
       when is_atom(machine_module) and is_integer(entry_index) do
    local_timeline_context = %TimelineContext{
      start_beat: BeatPosition.new(0, 0, 0),
      duration_ticks: timeline_context.duration_ticks
    }

    local_performance =
      chord_spec
      |> machine_module.render(sample_context, local_timeline_context)
      |> tag_sample_entry_index(entry_index)

    start_tick = TimelineContext.start_tick(timeline_context, sample_context)
    shift_performance(local_performance, start_tick, sample_context)
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
      granularity_ms: SampleContext.ticks_to_ms(sample_context, 6),
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
