defmodule Mensch.Machines.PulseRoot do
  @moduledoc """
  Machine that sustains only the chord root and adds short aftertouch pulses
  on each global beat boundary.

  Pulse timing uses absolute sample millibeats (passed in `opts`) so pulses stay
  aligned to the global beat grid even when the chord starts off-beat.
  With mbeat-native timing, frame steps divide one beat, so beat boundaries are
  already on the render lattice.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.RenderedEntry
  alias Mensch.Machines.PulseRootParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @mbeats_per_beat 1000

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

    frame_mbeats = SampleContext.frame_units(sample_context)

    pulse_width_mbeats =
      params.pulse_width_mbeats
      |> then(&SampleContext.mbeats_to_units(sample_context, &1))
      |> max(1)

    duration_mbeats =
      timeline_context
      |> TimelineContext.duration_mbeats()
      |> snap_mbeats(frame_mbeats)

    sample_start_mbeat =
      timeline_context
      |> TimelineContext.start_mbeat(sample_context)
      |> snap_mbeats(frame_mbeats)

    entry_start_mbeat_abs = Keyword.get(opts, :entry_start_mbeat_abs, sample_start_mbeat)

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
      delay_mbeats: sample_start_mbeat,
      total_mbeats: duration_mbeats,
      entry_start_mbeat_abs: entry_start_mbeat_abs,
      pulse_width_mbeats: pulse_width_mbeats,
      base_pressure: params.base_pressure,
      peak_pressure: params.peak_pressure
    }

    %RenderedEntry{
      duration_mbeats: duration_mbeats,
      music: build_music(note, duration_mbeats, frame_mbeats)
    }
  end

  defp build_music(note, duration_mbeats, frame_mbeats) do
    for at_mbeat <- 0..duration_mbeats//frame_mbeats do
      %{
        at_mbeat: at_mbeat,
        notes: [note_frame(note, at_mbeat, nil)]
      }
    end
  end

  defp note_frame(note, at_mbeat, _sample_context) when at_mbeat < note.delay_mbeats do
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

  defp note_frame(note, at_mbeat, _sample_context)
       when at_mbeat > note.delay_mbeats + note.total_mbeats do
    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
      phase: :ended,
      note_on: false,
      note_off: false,
      pressure: 0,
      bend: 0.0,
      slide: 0
    }
  end

  defp note_frame(note, at_mbeat, _sample_context) do
    local_elapsed_mbeats = at_mbeat - note.delay_mbeats
    absolute_mbeat = note.entry_start_mbeat_abs + at_mbeat

    pressure =
      beat_pulse_pressure(
        absolute_mbeat,
        note.pulse_width_mbeats,
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
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.total_mbeats,
      pressure: pressure,
      bend: 0.0,
      slide: 0
    }
  end

  defp beat_pulse_pressure(
         absolute_mbeat,
         pulse_width_mbeats,
         base_pressure,
         peak_pressure
       )
       when pulse_width_mbeats > 0 do
    phase_mbeats = rem(absolute_mbeat, @mbeats_per_beat)

    cond do
      phase_mbeats == 0 ->
        peak_pressure

      phase_mbeats < pulse_width_mbeats ->
        progress = phase_mbeats / pulse_width_mbeats
        interpolate(peak_pressure, base_pressure, progress)

      true ->
        base_pressure
    end
    |> clamp_7bit()
  end

  defp beat_pulse_pressure(
         _absolute_mbeat,
         _pulse_width_mbeats,
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

  defp snap_mbeats(mbeats, mbeats_per_frame),
    do: round(mbeats / mbeats_per_frame) * mbeats_per_frame

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
