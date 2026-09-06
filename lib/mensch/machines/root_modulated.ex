defmodule Mensch.Machines.RootModulated do
  @moduledoc """
  Machine that plays only the chord root for the full entry duration,
  while modulating pressure, bend, and slide over time.
  """

  @behaviour Mensch.Machine

  alias Mensch.ChordSpec
  alias Mensch.NoteShape
  alias Mensch.Performance
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @ticks_per_frame 6
  @velocity 100

  @attack_ms 90
  @decay_ms 120
  @release_ms 280

  @impl true
  def id, do: :root_modulated

  @impl true
  def controls do
    %{
      ticks_per_frame: @ticks_per_frame
    }
  end

  @impl true
  def render(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        _opts \\ []
      ) do
    duration_ticks = snap_ticks(timeline_context.duration_ticks, @ticks_per_frame)

    sample_start_tick =
      timeline_context
      |> TimelineContext.start_tick(sample_context)
      |> snap_ticks(@ticks_per_frame)

    root_note = midi_note_number(chord_spec.root, chord_spec.octave)
    {note_name, octave} = ChordSpec.note_name(root_note)

    milestones = build_milestones(duration_ticks, sample_context)

    note = %{
      note_name: note_name,
      octave: octave,
      note: root_note,
      channel: nil,
      velocity: @velocity,
      phase_offset: 0.0,
      emphasis: true,
      machine_id: id(),
      chord_instance_id: 0,
      event_index: 0,
      delay_ticks: sample_start_tick,
      milestones: milestones
    }

    duration_ms = SampleContext.ticks_to_ms(sample_context, duration_ticks)
    granularity_ms = SampleContext.ticks_to_ms(sample_context, @ticks_per_frame)

    %Performance{
      bpm: sample_context.bpm,
      time_signature: sample_context.time_signature,
      granularity_ms: granularity_ms,
      duration_ms: duration_ms,
      music: build_music(note, duration_ticks, sample_context)
    }
  end

  defp build_milestones(duration_ticks, %SampleContext{} = sample_context) do
    duration_ms = SampleContext.ticks_to_ms(sample_context, duration_ticks)

    %{
      attack_end_ms: @attack_ms,
      decay_end_ms: @attack_ms + @decay_ms,
      release_start_ms: max(duration_ms - @release_ms, 0),
      total_ms: duration_ms,
      total_ticks: duration_ticks
    }
  end

  defp build_music(note, duration_ticks, sample_context) do
    for at_tick <- 0..duration_ticks//@ticks_per_frame do
      at_ms = SampleContext.ticks_to_ms(sample_context, at_tick)

      %{
        at_ms: at_ms,
        at_tick: at_tick,
        notes: [note_frame(note, at_tick, sample_context)]
      }
    end
  end

  defp note_frame(note, at_tick, _sample_context) when at_tick < note.delay_ticks do
    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
      phase: :pending,
      note_on: false,
      note_off: false,
      pressure: 0,
      bend: 0.0,
      slide: 0
    }
  end

  defp note_frame(note, at_tick, sample_context) do
    local_elapsed_ticks = at_tick - note.delay_ticks
    local_elapsed_ms = SampleContext.ticks_to_ms(sample_context, local_elapsed_ticks)

    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
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

  defp midi_note_number(note, octave) do
    semitone =
      case note do
        :c -> 0
        :c_sharp -> 1
        :d -> 2
        :d_sharp -> 3
        :e -> 4
        :f -> 5
        :f_sharp -> 6
        :g -> 7
        :g_sharp -> 8
        :a -> 9
        :a_sharp -> 10
        :b -> 11
      end

    (octave + 1) * 12 + semitone
  end

  defp snap_ticks(ticks, ticks_per_frame), do: round(ticks / ticks_per_frame) * ticks_per_frame
  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end
