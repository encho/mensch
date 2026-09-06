defmodule Mensch.Render do
  @moduledoc """
  Facade that renders a performance via a concrete `Mensch.Machine`.

  `generate/0` is intentionally self-contained (single chord starting
  at time zero) for chord auditioning.

  Use `generate_song/0` or `generate_song/2` to render and aggregate a
  full multi-entry song timeline.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machines.StrummedMpe
  alias Mensch.Performance
  alias Mensch.SongContext
  alias Mensch.TimelineContext
  alias Mensch.BeatPosition

  @default_spec %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0}
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
        start_beat: %BeatPosition{bar: 2, beat: 0, tick: 0},
        duration_ticks: 384
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

  @doc "Renders the default chord (`C4 maj7`, root position) using the default machine."
  @spec generate() :: Performance.t()
  def generate do
    StrummedMpe.render(@default_spec, @default_song_context, @default_timeline_context)
  end

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
  end

  @doc "Returns the default song entries for UI/debug display."
  @spec default_song_entries() :: [map()]
  def default_song_entries, do: @default_song_entries

  @doc "Returns the default song context used by `generate/0` and `generate_song/0`."
  @spec default_song_context() :: SongContext.t()
  def default_song_context, do: @default_song_context

  @doc "Renders the given chord spec using default song/timeline contexts."
  @spec generate(ChordSpec.t()) :: Performance.t()
  def generate(%ChordSpec{} = chord_spec) do
    StrummedMpe.render(chord_spec, @default_song_context, @default_timeline_context)
  end

  @doc "Renders a chord spec with an explicit song/timeline context via the default machine."
  @spec generate(ChordSpec.t(), SongContext.t(), TimelineContext.t()) :: Performance.t()
  def generate(
        %ChordSpec{} = chord_spec,
        %SongContext{} = song_context,
        %TimelineContext{} = timeline_context
      ) do
    StrummedMpe.render(chord_spec, song_context, timeline_context)
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
    end_tick = TimelineContext.end_tick(timeline_context, song_context)

    shift_and_clip_performance(local_performance, start_tick, end_tick, song_context)
  end

  defp shift_and_clip_performance(
         %Performance{} = performance,
         start_tick,
         end_tick,
         %SongContext{} = song_context
       ) do
    shifted_frames =
      performance.music
      |> Enum.map(fn frame ->
        shifted_tick = frame.at_tick + start_tick

        %{
          at_tick: shifted_tick,
          at_ms: SongContext.ticks_to_ms(song_context, shifted_tick),
          notes: frame.notes
        }
      end)
      |> Enum.filter(&(&1.at_tick <= end_tick))

    forced_off_notes = forced_note_offs(shifted_frames)

    clipped_music =
      shifted_frames
      |> insert_forced_off_frame(forced_off_notes, end_tick, song_context)
      |> Enum.sort_by(& &1.at_tick)

    %Performance{
      performance
      | duration_ms: SongContext.ticks_to_ms(song_context, end_tick),
        music: clipped_music
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

  defp forced_note_offs(shifted_frames) do
    shifted_frames
    |> Enum.flat_map(fn frame ->
      Enum.map(frame.notes, fn note ->
        {{note.channel, note.note}, note}
      end)
    end)
    |> Enum.reduce(%{}, fn {{channel, note_number} = note_id, note}, acc ->
      state = Map.get(acc, note_id, %{last: nil, on?: false, off?: false})

      Map.put(acc, note_id, %{
        last: note,
        on?: state.on? or note.note_on,
        off?: state.off? or note.note_off,
        channel: channel,
        note: note_number
      })
    end)
    |> Enum.flat_map(fn {{_channel, _note_number}, state} ->
      if state.on? and not state.off? do
        [%{state.last | note_on: false, note_off: true, pressure: 0, bend: 0.0, slide: 0}]
      else
        []
      end
    end)
  end

  defp insert_forced_off_frame(frames, [], _end_tick, _song_context), do: frames

  defp insert_forced_off_frame(frames, forced_off_notes, end_tick, %SongContext{} = song_context) do
    {at_end, other} = Enum.split_with(frames, &(&1.at_tick == end_tick))

    end_frame =
      case at_end do
        [existing] ->
          %{existing | notes: existing.notes ++ forced_off_notes}

        [] ->
          %{
            at_tick: end_tick,
            at_ms: SongContext.ticks_to_ms(song_context, end_tick),
            notes: forced_off_notes
          }
      end

    [end_frame | other]
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
end
