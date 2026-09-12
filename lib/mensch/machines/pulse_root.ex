defmodule Mensch.Machines.PulseRoot do
  @moduledoc """
  Machine that sustains only the chord root and adds short aftertouch pulses
  on each global beat boundary.

  Pulse timing uses absolute sample ticks (passed in `opts`) so pulses stay
  aligned to the global beat grid even when the chord starts off-beat.
  With mbeat-native timing, frame steps divide one beat, so beat boundaries are
  already on the render lattice.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machines.PulseRootParams
  alias Mensch.Performance
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @type t :: %__MODULE__{params: PulseRootParams.t()}

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :pulse_root

  def params_module, do: PulseRootParams

  def default_params, do: PulseRootParams.default()

  @spec new(PulseRootParams.t()) :: t()
  def new(%PulseRootParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  def controls do
    params = default_params()

    %{
      base_pressure: params.base_pressure,
      peak_pressure: params.peak_pressure,
      pulse_width_mbeats: params.pulse_width_mbeats
    }
  end

  def render(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %PulseRootParams{} = params = machine_params!(opts)

    frame_ticks = SampleContext.frame_ticks(sample_context)

    pulse_width_ticks =
      params.pulse_width_mbeats
      |> then(&SampleContext.mbeats_to_ticks(sample_context, &1))
      |> max(1)

    duration_ticks =
      timeline_context
      |> TimelineContext.duration_ticks(sample_context)
      |> snap_ticks(frame_ticks)

    sample_start_tick =
      timeline_context
      |> TimelineContext.start_tick(sample_context)
      |> snap_ticks(frame_ticks)

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
      velocity: params.velocity,
      machine_id: id(),
      chord_instance_id: 0,
      event_index: 0,
      delay_ticks: sample_start_tick,
      total_ticks: duration_ticks,
      entry_start_tick_abs: entry_start_tick_abs,
      ticks_per_beat: ticks_per_beat,
      pulse_width_ticks: pulse_width_ticks,
      base_pressure: params.base_pressure,
      peak_pressure: params.peak_pressure
    }

    duration_ms = SampleContext.ticks_to_ms(sample_context, duration_ticks)
    granularity_ms = SampleContext.ticks_to_ms(sample_context, frame_ticks)

    %Performance{
      bpm: sample_context.bpm,
      time_signature: sample_context.time_signature,
      granularity_ms: granularity_ms,
      duration_ms: duration_ms,
      music: build_music(note, duration_ticks, sample_context, frame_ticks)
    }
  end

  defp build_music(note, duration_ticks, sample_context, frame_ticks) do
    for at_tick <- 0..duration_ticks//frame_ticks do
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

  defp note_frame(note, at_tick, _sample_context) do
    local_elapsed_ticks = at_tick - note.delay_ticks
    absolute_tick = note.entry_start_tick_abs + at_tick

    pressure =
      beat_pulse_pressure(
        absolute_tick,
        note.ticks_per_beat,
        note.pulse_width_ticks,
        note.base_pressure,
        note.peak_pressure
      )

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

  defp beat_pulse_pressure(
         absolute_tick,
         ticks_per_beat,
         pulse_width_ticks,
         base_pressure,
         peak_pressure
       )
       when ticks_per_beat > 0 and pulse_width_ticks > 0 do
    phase_ticks = rem(absolute_tick, ticks_per_beat)

    cond do
      phase_ticks == 0 ->
        peak_pressure

      phase_ticks < pulse_width_ticks ->
        progress = phase_ticks / pulse_width_ticks
        interpolate(peak_pressure, base_pressure, progress)

      true ->
        base_pressure
    end
    |> clamp_7bit()
  end

  defp beat_pulse_pressure(
         _absolute_tick,
         _ticks_per_beat,
         _pulse_width_ticks,
         base_pressure,
         _peak_pressure
       ),
       do: base_pressure

  defp machine_params!(opts) do
    case Keyword.fetch(opts, :machine_params) do
      {:ok, %PulseRootParams{} = params} ->
        params

      {:ok, other} ->
        raise ArgumentError,
              "expected #{inspect(PulseRootParams)} in :machine_params, got #{inspect(other)}"

      :error ->
        raise ArgumentError, "missing :machine_params for #{inspect(__MODULE__)}"
    end
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

defimpl Mensch.Machine, for: Mensch.Machines.PulseRoot do
  alias Mensch.Machines.PulseRoot

  def id(_machine), do: PulseRoot.id()

  def controls(%PulseRoot{params: params}) do
    %{
      base_pressure: params.base_pressure,
      peak_pressure: params.peak_pressure,
      pulse_width_mbeats: params.pulse_width_mbeats
    }
  end

  def render(%PulseRoot{params: params}, chord_spec, sample_context, timeline_context, opts) do
    PulseRoot.render(
      chord_spec,
      sample_context,
      timeline_context,
      Keyword.put(opts, :machine_params, params)
    )
  end
end
