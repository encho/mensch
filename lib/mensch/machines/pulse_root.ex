defmodule Mensch.Machines.PulseRoot do
  @moduledoc """
  Machine that sustains only the chord root and adds short aftertouch pulses
  on each global beat boundary.

  Pulse timing uses absolute sample ticks (passed in `opts`) so pulses stay
  aligned to the global beat grid even when the chord starts off-beat.
  Beat-boundary frames are inserted explicitly so pulse peaks can land exactly
  on the beat tick even when the base frame grid is off-phase.
  """

  @behaviour Mensch.Machine

  alias Mensch.ChordSpec
  alias Mensch.Performance
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @ticks_per_frame 6
  @velocity 100

  @base_pressure 30
  @peak_pressure 95
  @pulse_width_ms 60

  @impl true
  def id, do: :pulse_root

  @impl true
  def controls do
    %{
      ticks_per_frame: @ticks_per_frame,
      base_pressure: @base_pressure,
      peak_pressure: @peak_pressure,
      pulse_width_ms: @pulse_width_ms
    }
  end

  @impl true
  def render(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    duration_ticks = snap_ticks(timeline_context.duration_ticks, @ticks_per_frame)

    sample_start_tick =
      timeline_context
      |> TimelineContext.start_tick(sample_context)
      |> snap_ticks(@ticks_per_frame)

    entry_start_tick_abs = Keyword.get(opts, :entry_start_tick_abs, sample_start_tick)

    ticks_per_beat =
      Keyword.get(opts, :ticks_per_beat, SampleContext.ticks_per_beat(sample_context))

    root_note = midi_note_number(chord_spec.root, chord_spec.octave)
    {note_name, octave} = ChordSpec.note_name(root_note)

    note = %{
      note_name: note_name,
      octave: octave,
      note: root_note,
      channel: nil,
      velocity: @velocity,
      machine_id: id(),
      chord_instance_id: 0,
      event_index: 0,
      delay_ticks: sample_start_tick,
      total_ticks: duration_ticks,
      entry_start_tick_abs: entry_start_tick_abs,
      ticks_per_beat: ticks_per_beat
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

  defp build_music(note, duration_ticks, sample_context) do
    for at_tick <- timeline_ticks(note, duration_ticks) do
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
    absolute_tick = note.entry_start_tick_abs + at_tick
    pressure = beat_pulse_pressure(absolute_tick, note.ticks_per_beat, sample_context)

    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
      phase: :sustain,
      note_on: local_elapsed_ticks == 0,
      note_off: local_elapsed_ticks == note.total_ticks,
      pressure: pressure,
      bend: 0.0,
      slide: 0
    }
  end

  defp beat_pulse_pressure(absolute_tick, ticks_per_beat, sample_context)
       when ticks_per_beat > 0 do
    phase_ticks = rem(absolute_tick, ticks_per_beat)
    phase_ms = SampleContext.ticks_to_ms(sample_context, phase_ticks)

    cond do
      phase_ticks == 0 ->
        @peak_pressure

      phase_ms < @pulse_width_ms ->
        progress = phase_ms / @pulse_width_ms
        interpolate(@peak_pressure, @base_pressure, progress)

      true ->
        @base_pressure
    end
    |> clamp_7bit()
  end

  defp beat_pulse_pressure(_absolute_tick, _ticks_per_beat, _sample_context), do: @base_pressure

  defp timeline_ticks(note, duration_ticks) do
    base_ticks = Enum.to_list(0..duration_ticks//@ticks_per_frame)
    beat_ticks = beat_ticks_within(note.entry_start_tick_abs, note.ticks_per_beat, duration_ticks)

    (base_ticks ++ beat_ticks)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp beat_ticks_within(_entry_start_tick_abs, ticks_per_beat, _duration_ticks)
       when ticks_per_beat <= 0,
       do: []

  defp beat_ticks_within(entry_start_tick_abs, ticks_per_beat, duration_ticks) do
    start_phase = rem(entry_start_tick_abs, ticks_per_beat)
    first_beat_local_tick = if start_phase == 0, do: 0, else: ticks_per_beat - start_phase

    first_beat_local_tick..duration_ticks//ticks_per_beat
    |> Enum.to_list()
  end

  defp interpolate(from, to, progress) do
    from + (to - from) * progress
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
