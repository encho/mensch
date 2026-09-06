defmodule Mensch.Render do
  @moduledoc """
  Precomputes a hardcoded C4 maj7 chord's full MPE performance ahead
  of time, as a plain, inspectable data structure - instead of a live
  reactive process tree. Samples the same per-note shaping math a live
  player would (see `Mensch.NoteShape`), just ahead of time, over each
  note's whole life, instead of tick by tick in real time.

  Two voicings of the chord play: the C4 maj7 shape itself, then the
  same shape again one octave lower (C3 maj7) entering `@chord_stagger_ms`
  later, like a bass chord following the first - widening the range of
  notes actually sounding (handy for eyeballing the note matrix).

  The result is a single, self-describing `%Mensch.Performance{}`:

      %Mensch.Performance{
        bpm: 120,
        time_signature: {4, 4},
        granularity_ms: 30,
        duration_ms: 2490,
        music: [
          %{at_ms: 0, notes: [%{note_name: :c, octave: 4, note: 60, channel: 1,
                                 velocity: 100, phase: :attack, note_on: true,
                                 note_off: false, pressure: 0, bend: 0.0, slide: 0}, ...]},
          %{at_ms: 30, notes: [...]},
          ...
        ]
      }

  `music` is one continuous timeline (`at_ms` measured from `0` at the
  very start of the first chord) with one frame per `granularity_ms`
  tick, and every note (across both chords) gets its own attack/decay/
  sustain/release envelope (each one identically shaped, from the same
  `@attack_ms`/`@decay_ms`/`@release_ms`/`@duration_ms`), but staggered:
  each chord tone's envelope starts `@stagger_ms` later than the one
  before it within its own chord (a light strum), and the lower-octave
  chord as a whole starts `@chord_stagger_ms` after the first - so
  `note_on`/`note_off` fire at a different `at_ms` per note instead of
  all eight in lockstep. Before a note's own envelope has started, its
  frame is a silent placeholder (`phase: :pending`, everything else at
  rest) - `note_on`/`note_off` still mark the two discrete MIDI wire
  events (Note On with `velocity`, Note Off) for that note; `phase`
  otherwise describes which part of its envelope it's currently in.
  """

  alias Mensch.Midi.Connection
  alias Mensch.NoteShape
  alias Mensch.Performance

  @bpm 120
  @time_signature {4, 4}
  @granularity_ms 30
  @velocity 100

  # C major 7th (root, major 3rd, perfect 5th, major 7th), octave 4.
  @chord [c: 4, e: 4, g: 4, b: 4]

  # The same chord shape again, one octave lower - widens the range of
  # notes sounding at once (see the note matrix) and enters staggered
  # behind the first (see `@chord_stagger_ms`).
  @chord_octave_shifts [0, -2]

  @attack_ms 100
  @decay_ms 100
  @release_ms 250
  @duration_ms 2000

  # How much later than the previous chord tone each next one starts
  # its own envelope - a light strum instead of all notes within a
  # chord attacking in perfect lockstep.
  @stagger_ms 60

  # How much later than the first chord the next one (one octave
  # lower) starts, as a whole - so the two chords don't sound together.
  @chord_stagger_ms 300

  @notes ~w(c c_sharp d d_sharp e f f_sharp g g_sharp a a_sharp b)a

  @doc "Generates the full performance dataset for the hardcoded C4 maj7 chord (plus a staggered echo one octave down)."
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
      for {octave_shift, chord_index} <- Enum.with_index(@chord_octave_shifts),
          {{note_name, octave}, note_index} <- Enum.with_index(@chord) do
        chord_delay_ms = chord_index * @chord_stagger_ms
        note_delay_ms = chord_delay_ms + note_index * @stagger_ms

        %{
          note_name: note_name,
          octave: octave + octave_shift,
          note: midi_note_number(note_name, octave + octave_shift),
          channel: Enum.at(channels, chord_index * note_count + note_index),
          velocity: @velocity,
          phase_offset: note_index / note_count * 2 * :math.pi(),
          emphasis: note_index == 0,
          delay_ms: snap(note_delay_ms, @granularity_ms),
          milestones: milestones
        }
      end

    duration_ms = notes |> Enum.map(&(&1.delay_ms + &1.milestones.total_ms)) |> Enum.max()

    %Performance{
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

  @doc "The note name and octave for a MIDI note number, e.g. `64` -> `{:e, 4}`."
  def note_name(note_number) do
    octave = div(note_number, 12) - 1
    semitone = rem(note_number, 12)
    {Enum.at(@notes, semitone), octave}
  end

  # Rounds `ms` to the nearest multiple of `granularity_ms`, so the
  # chord's own end always lands exactly on a frame boundary.
  defp snap(ms, granularity_ms), do: round(ms / granularity_ms) * granularity_ms

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end
