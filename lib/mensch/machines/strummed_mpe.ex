defmodule Mensch.Machines.StrummedMpe do
  @moduledoc """
  First concrete machine implementation.

  Renders a strummed, per-note-envelope MPE performance from a generic
  `Mensch.ChordSpec`, including a second voicing two octaves below,
  staggered in time.
  """

  @behaviour Mensch.Machine

  alias Mensch.ChordSpec
  alias Mensch.Midi.Connection
  alias Mensch.NoteShape
  alias Mensch.Performance
  alias Mensch.SongContext
  alias Mensch.TimelineContext

  @ticks_per_frame 6
  @velocity 100

  @attack_ms 100
  @decay_ms 100
  @release_ms 250

  # Within-chord strum spacing.
  @note_stagger_ms 60
  # Inter-chord spacing (upper voicing, then lower voicing).
  @chord_stagger_ms 300
  @octave_shifts [0, -2]

  @impl true
  def id, do: :strummed_mpe

  @impl true
  def controls do
    %{
      note_stagger_ms: @note_stagger_ms,
      chord_stagger_ms: @chord_stagger_ms,
      octave_shifts: @octave_shifts,
      ticks_per_frame: @ticks_per_frame
    }
  end

  @impl true
  def render(
        %ChordSpec{} = chord_spec,
        %SongContext{} = song_context,
        %TimelineContext{} = timeline_context,
        _opts \\ []
      ) do
    channels = Connection.member_channels()

    note_stagger_ticks =
      @note_stagger_ms
      |> then(&SongContext.ms_to_ticks(song_context, &1))
      |> snap_ticks(@ticks_per_frame)

    chord_stagger_ticks =
      @chord_stagger_ms
      |> then(&SongContext.ms_to_ticks(song_context, &1))
      |> snap_ticks(@ticks_per_frame)

    note_duration_ticks = snap_ticks(timeline_context.duration_ticks, @ticks_per_frame)
    note_duration_ms = SongContext.ticks_to_ms(song_context, note_duration_ticks)

    song_start_tick =
      timeline_context
      |> TimelineContext.start_tick(song_context)
      |> snap_ticks(@ticks_per_frame)

    milestones = %{
      attack_end_ms: @attack_ms,
      decay_end_ms: @attack_ms + @decay_ms,
      release_start_ms: max(note_duration_ms - @release_ms, 0),
      total_ms: note_duration_ms,
      total_ticks: note_duration_ticks
    }

    notes =
      build_notes(
        chord_spec,
        channels,
        milestones,
        song_start_tick,
        note_stagger_ticks,
        chord_stagger_ticks
      )

    duration_ticks =
      notes |> Enum.map(&(&1.delay_ticks + &1.milestones.total_ticks)) |> Enum.max()

    duration_ms = SongContext.ticks_to_ms(song_context, duration_ticks)
    granularity_ms = SongContext.ticks_to_ms(song_context, @ticks_per_frame)

    %Performance{
      bpm: song_context.bpm,
      time_signature: song_context.time_signature,
      granularity_ms: granularity_ms,
      duration_ms: duration_ms,
      music: build_music(notes, duration_ticks, song_context)
    }
  end

  defp build_notes(
         chord_spec,
         channels,
         milestones,
         song_start_tick,
         note_stagger_ticks,
         chord_stagger_ticks
       ) do
    note_count = chord_note_count(chord_spec)

    for {octave_shift, chord_index} <- Enum.with_index(@octave_shifts),
        {note_number, note_index} <-
          chord_spec
          |> shifted_spec(octave_shift)
          |> ChordSpec.to_midi_notes()
          |> Enum.with_index() do
      chord_delay_ticks = chord_index * chord_stagger_ticks
      note_delay_ticks = chord_delay_ticks + note_index * note_stagger_ticks
      {note_name, octave} = ChordSpec.note_name(note_number)

      %{
        note_name: note_name,
        octave: octave,
        note: note_number,
        channel: Enum.at(channels, chord_index * note_count + note_index),
        velocity: @velocity,
        phase_offset: note_index / note_count * 2 * :math.pi(),
        emphasis: note_index == 0,
        delay_ticks: song_start_tick + note_delay_ticks,
        milestones: milestones
      }
    end
  end

  defp chord_note_count(chord_spec) do
    chord_spec
    |> ChordSpec.to_midi_notes()
    |> length()
  end

  defp shifted_spec(%ChordSpec{} = chord_spec, octave_shift) do
    %{chord_spec | octave: chord_spec.octave + octave_shift}
  end

  defp build_music(notes, duration_ticks, song_context) do
    for at_tick <- 0..duration_ticks//@ticks_per_frame do
      at_ms = SongContext.ticks_to_ms(song_context, at_tick)

      %{
        at_ms: at_ms,
        at_tick: at_tick,
        notes: Enum.map(notes, &note_frame(&1, at_tick, song_context))
      }
    end
  end

  defp note_frame(note, at_tick, _song_context) when at_tick < note.delay_ticks do
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

  defp note_frame(note, at_tick, song_context) do
    local_elapsed_ticks = at_tick - note.delay_ticks
    local_elapsed_ms = SongContext.ticks_to_ms(song_context, local_elapsed_ticks)

    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      phase: NoteShape.phase_at(note.milestones, local_elapsed_ms),
      note_on: local_elapsed_ticks == 0,
      note_off: local_elapsed_ticks == note.milestones.total_ticks,
      pressure:
        NoteShape.pressure(note.milestones, note.phase_offset, local_elapsed_ms)
        |> clamp_7bit(),
      bend: NoteShape.bend(note.milestones, note.phase_offset, local_elapsed_ms),
      slide:
        NoteShape.slide(note.milestones, note.phase_offset, note.emphasis, local_elapsed_ms)
        |> clamp_7bit()
    }
  end

  defp snap_ticks(ticks, ticks_per_frame), do: round(ticks / ticks_per_frame) * ticks_per_frame
  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end
