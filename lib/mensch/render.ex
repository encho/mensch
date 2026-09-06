defmodule Mensch.Render do
  @moduledoc """
  Facade that renders a performance via a concrete `Mensch.Machine`.

  Use `generate_song/0` or `generate_song/2` to render and aggregate a
  full multi-entry song timeline.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machines.StrummedMpe
  alias Mensch.Midi.Connection
  alias Mensch.Performance
  alias Mensch.SongContext
  alias Mensch.TimelineContext
  alias Mensch.BeatPosition

  @default_song_context %SongContext{bpm: 120, time_signature: {4, 4}, ppq: 96}
  @default_timeline_context %TimelineContext{
    start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
    duration_ticks: 384
  }

  @default_song_entries [
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

  @default_song_two_context %SongContext{bpm: 80, time_signature: {4, 4}, ppq: 96}
  @default_song_two_entries [
    %{
      chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
        duration_ticks: 1536
      },
      machine_module: StrummedMpe
    }
  ]

  @default_songs [
    %{
      id: "song-1",
      name: "Song 1 · Dm7 G7 Cmaj7",
      song_context: @default_song_context,
      song_entries: @default_song_entries
    },
    %{
      id: "song-2",
      name: "Song 2 · Cmaj7 Drone",
      song_context: @default_song_two_context,
      song_entries: @default_song_two_entries
    }
  ]

  @doc "Default multi-entry song render (aggregated timeline)."
  @spec generate_song() :: Performance.t()
  def generate_song do
    generate_song(@default_song_entries, @default_song_context)
  end

  @doc "Renders and aggregates a full song timeline from entry maps."
  @spec generate_song([map()], SongContext.t()) :: Performance.t()
  def generate_song(entries, %SongContext{} = song_context) when is_list(entries) do
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
        song_context,
        entry_index
      )
    end)
    |> merge_performances(song_context)
    |> rechannelize_performance()
  end

  @doc "Returns the default song entries for UI/debug display."
  @spec default_song_entries() :: [map()]
  def default_song_entries, do: @default_song_entries

  @doc "Returns the default song catalog for UI selection."
  @spec default_songs() :: [map()]
  def default_songs, do: @default_songs

  @doc "Returns the default song context used by `generate_song/0`."
  @spec default_song_context() :: SongContext.t()
  def default_song_context, do: @default_song_context

  @doc "Renders the given chord spec using default song/timeline contexts."
  @spec generate(ChordSpec.t()) :: Performance.t()
  def generate(%ChordSpec{} = chord_spec) do
    StrummedMpe.render(chord_spec, @default_song_context, @default_timeline_context)
    |> rechannelize_performance()
  end

  @doc "Renders a chord spec with an explicit song/timeline context via the default machine."
  @spec generate(ChordSpec.t(), SongContext.t(), TimelineContext.t()) :: Performance.t()
  def generate(
        %ChordSpec{} = chord_spec,
        %SongContext{} = song_context,
        %TimelineContext{} = timeline_context
      ) do
    StrummedMpe.render(chord_spec, song_context, timeline_context)
    |> rechannelize_performance()
  end

  @doc "Renders a chord spec via a specific machine module implementing `Mensch.Machine`."
  @spec generate(ChordSpec.t(), SongContext.t(), TimelineContext.t(), module()) :: Performance.t()
  def generate(
        %ChordSpec{} = chord_spec,
        %SongContext{} = song_context,
        %TimelineContext{} = timeline_context,
        machine_module
      )
      when is_atom(machine_module) do
    machine_module.render(chord_spec, song_context, timeline_context)
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
         %SongContext{} = song_context,
         entry_index
       )
       when is_atom(machine_module) and is_integer(entry_index) do
    local_timeline_context = %TimelineContext{
      start_beat: BeatPosition.new(0, 0, 0),
      duration_ticks: timeline_context.duration_ticks
    }

    local_performance =
      chord_spec
      |> machine_module.render(song_context, local_timeline_context)
      |> tag_song_entry_index(entry_index)

    start_tick = TimelineContext.start_tick(timeline_context, song_context)
    shift_performance(local_performance, start_tick, song_context)
  end

  defp shift_performance(
         %Performance{} = performance,
         start_tick,
         %SongContext{} = song_context
       ) do
    shifted_music =
      Enum.map(performance.music, fn frame ->
        shifted_tick = frame.at_tick + start_tick

        %{
          at_tick: shifted_tick,
          at_ms: SongContext.ticks_to_ms(song_context, shifted_tick),
          notes: frame.notes
        }
      end)

    last_tick = shifted_music |> List.last() |> then(&if(&1, do: &1.at_tick, else: 0))

    %Performance{
      performance
      | duration_ms: SongContext.ticks_to_ms(song_context, last_tick),
        music: shifted_music
    }
  end

  defp tag_song_entry_index(%Performance{} = performance, entry_index) do
    tagged_music =
      Enum.map(performance.music, fn frame ->
        tagged_notes =
          Enum.map(frame.notes, fn note ->
            Map.put(note, :song_entry_index, entry_index)
          end)

        %{frame | notes: tagged_notes}
      end)

    %Performance{performance | music: tagged_music}
  end

  defp merge_performances([], %SongContext{} = song_context) do
    %Performance{
      bpm: song_context.bpm,
      time_signature: song_context.time_signature,
      granularity_ms: SongContext.ticks_to_ms(song_context, 6),
      duration_ms: 0,
      music: []
    }
  end

  defp merge_performances(performances, %SongContext{} = song_context) do
    merged_music =
      performances
      |> Enum.flat_map(& &1.music)
      |> Enum.group_by(& &1.at_tick)
      |> Enum.map(fn {at_tick, frames} ->
        %{
          at_tick: at_tick,
          at_ms: SongContext.ticks_to_ms(song_context, at_tick),
          notes: Enum.flat_map(frames, & &1.notes)
        }
      end)
      |> Enum.sort_by(& &1.at_tick)

    %Performance{
      bpm: song_context.bpm,
      time_signature: song_context.time_signature,
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
      Map.get(note, :song_entry_index, -1),
      Map.get(note, :machine_id, :unknown),
      Map.get(note, :chord_instance_id, 0),
      Map.get(note, :event_index, 0),
      note.note
    }
  end
end
