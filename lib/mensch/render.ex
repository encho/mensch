defmodule Mensch.Render do
  @moduledoc """
  Precomputes a hardcoded C4 maj7 chord's full MPE performance ahead
  of time, as a plain, inspectable data structure - instead of a live
  reactive process tree. Samples the same per-note shaping math a live
  player would (see `Mensch.NoteShape`), just ahead of time, over each
  note's whole life, instead of tick by tick in real time.

  The result is a single, self-describing map:

      %{
        bpm: 120,
        time_signature: {4, 4},
        granularity_ms: 30,
        duration_ms: 2070,
        music: [
          %{at_ms: 0, notes: [%{note_name: :c, octave: 4, note: 60, channel: 1,
                                 velocity: 100, phase: :attack, note_on: true,
                                 note_off: false, pressure: 0, bend: 0.0, slide: 0}, ...]},
          %{at_ms: 30, notes: [...]},
          ...
        ]
      }

  `music` is one continuous timeline (`at_ms` measured from `0` at the
  very start of the chord) with one frame per `granularity_ms` tick,
  and every note gets its own attack/decay/sustain/release envelope
  (each one identically shaped, from the same chord-level
  `@attack_ms`/`@decay_ms`/`@release_ms`/`@duration_ms`), but staggered:
  each chord tone's envelope starts `@stagger_ms` later than the one
  before it (a light strum), so `note_on`/`note_off` fire at a
  different `at_ms` per note instead of all four in lockstep. Before a
  note's own envelope has started, its frame is a silent placeholder
  (`phase: :pending`, everything else at rest) - `note_on`/`note_off`
  still mark the two discrete MIDI wire events (Note On with
  `velocity`, Note Off) for that note; `phase` otherwise describes
  which part of its envelope it's currently in.
  """

  alias Mensch.Midi.Connection
  alias Mensch.NoteShape

  @bpm 120
  @time_signature {4, 4}
  @granularity_ms 30
  @velocity 100

  # C major 7th (root, major 3rd, perfect 5th, major 7th), octave 4.
  @chord [c: 4, e: 4, g: 4, b: 4]

  @attack_ms 100
  @decay_ms 100
  @release_ms 250
  @duration_ms 2000

  # How much later than the previous chord tone each next one starts
  # its own envelope - a light strum instead of all four notes
  # attacking in perfect lockstep.
  @stagger_ms 60

  @notes ~w(c c_sharp d d_sharp e f f_sharp g g_sharp a a_sharp b)a

  @doc "Generates the full performance dataset for the hardcoded C4 maj7 chord."
  def generate do
    channels = Connection.member_channels()
    note_count = length(@chord)

    # Snapped to the tick grid up front so each note's own envelope
    # always lands exactly on a frame boundary - the loop below builds
    # one tick per `at_ms in 0..duration_ms`, so a note's `note_off`
    # (`local_elapsed_ms == note.milestones.total_ms`) must compare
    # against this same snapped value.
    note_duration_ms = snap(@duration_ms, @granularity_ms)

    # Every note's own envelope is identically shaped - only its start
    # time (`delay_ms`) differs.
    milestones = %{
      attack_end_ms: @attack_ms,
      decay_end_ms: @attack_ms + @decay_ms,
      release_start_ms: note_duration_ms - @release_ms,
      total_ms: note_duration_ms
    }

    notes =
      @chord
      |> Enum.with_index()
      |> Enum.map(fn {{note_name, octave}, index} ->
        %{
          note_name: note_name,
          octave: octave,
          note: midi_note_number(note_name, octave),
          channel: Enum.at(channels, index),
          velocity: @velocity,
          phase_offset: index / note_count * 2 * :math.pi(),
          emphasis: index == 0,
          delay_ms: snap(index * @stagger_ms, @granularity_ms),
          milestones: milestones
        }
      end)

    duration_ms = notes |> Enum.map(&(&1.delay_ms + &1.milestones.total_ms)) |> Enum.max()

    %{
      bpm: @bpm,
      time_signature: @time_signature,
      granularity_ms: @granularity_ms,
      duration_ms: duration_ms,
      music: build_music(notes, duration_ms)
    }
  end

  defp build_music(notes, duration_ms) do
    tick_count = div(duration_ms, @granularity_ms)

    for tick <- 0..tick_count do
      at_ms = tick * @granularity_ms
      %{at_ms: at_ms, notes: Enum.map(notes, &note_frame(&1, at_ms))}
    end
  end

  # Before this note's own (delayed) envelope has started, it's a
  # silent placeholder - not yet on, nothing to shape.
  defp note_frame(note, at_ms) when at_ms < note.delay_ms do
    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      phase: :pending,
      note_on: false,
      note_off: false,
      pressure: 0,
      bend: 0.0,
      slide: 0
    }
  end

  defp note_frame(note, at_ms) do
    local_elapsed_ms = at_ms - note.delay_ms

    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      phase: NoteShape.phase_at(note.milestones, local_elapsed_ms),
      note_on: local_elapsed_ms == 0,
      note_off: local_elapsed_ms == note.milestones.total_ms,
      pressure:
        NoteShape.pressure(note.milestones, note.phase_offset, local_elapsed_ms)
        |> clamp_7bit(),
      bend: NoteShape.bend(note.milestones, note.phase_offset, local_elapsed_ms),
      slide:
        NoteShape.slide(note.milestones, note.phase_offset, note.emphasis, local_elapsed_ms)
        |> clamp_7bit()
    }
  end

  defp midi_note_number(note, octave) do
    semitone = Enum.find_index(@notes, &(&1 == note))
    (octave + 1) * 12 + semitone
  end

  # Rounds `ms` to the nearest multiple of `granularity_ms`, so the
  # chord's own end always lands exactly on a frame boundary.
  defp snap(ms, granularity_ms), do: round(ms / granularity_ms) * granularity_ms

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end
