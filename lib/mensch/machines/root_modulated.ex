defmodule Mensch.Machines.RootModulated do
  @moduledoc """
  Machine that plays only the chord root for the full entry duration,
  while modulating pressure, bend, and slide over time.
  """

  alias Mensch.ChordSpec
  alias Mensch.Envelope.ADSR
  alias Mensch.Machine.MachineFrameSequence
  alias Mensch.Machines.RootModulatedParams
  alias Mensch.NoteShape
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @type t :: %__MODULE__{params: RootModulatedParams.t()}

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :root_modulated

  def params_module, do: RootModulatedParams

  def default_params, do: RootModulatedParams.default()

  @spec new(RootModulatedParams.t()) :: t()
  def new(%RootModulatedParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  def controls do
    %{}
  end

  def build_frame_sequence(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %RootModulatedParams{} = params = machine_params!(opts)

    frame_mbeats = SampleContext.frame_units(sample_context)

    duration_mbeats =
      timeline_context
      |> TimelineContext.duration_mbeats()
      |> snap_mbeats(frame_mbeats)

    sample_start_mbeat =
      timeline_context
      |> TimelineContext.start_mbeat(sample_context)
      |> snap_mbeats(frame_mbeats)

    root_note = midi_note_number(chord_spec.root, chord_spec.octave)
    {note_name, octave} = ChordSpec.note_name(root_note)

    adsr = build_adsr(duration_mbeats, sample_context, params)

    note = %{
      note_name: note_name,
      octave: octave,
      midi_note: root_note,
      channel: nil,
      velocity: params.velocity,
      phase_offset: 0.0,
      emphasis: true,
      machine_id: id(),
      chord_instance_id: 0,
      event_index: 0,
      delay_mbeats: sample_start_mbeat,
      adsr: adsr
    }

    %MachineFrameSequence{
      frames: build_frames(note, duration_mbeats, frame_mbeats, sample_context)
    }
  end

  defp build_adsr(
         duration_mbeats,
         %SampleContext{} = sample_context,
         %RootModulatedParams{} = params
       ) do
    ADSR.from_mbeats(duration_mbeats, sample_context, %{
      attack_mbeats: params.attack_mbeats,
      decay_mbeats: params.decay_mbeats,
      release_mbeats: params.release_mbeats
    })
  end

  defp build_frames(note, duration_mbeats, frame_mbeats, sample_context) do
    for at_mbeat <- 0..duration_mbeats//frame_mbeats do
      %{
        at_mbeat: at_mbeat,
        notes: [note_frame(note, at_mbeat, sample_context)]
      }
    end
  end

  defp machine_params!(opts) do
    case Keyword.fetch(opts, :machine_params) do
      {:ok, %RootModulatedParams{} = params} ->
        params

      {:ok, other} ->
        raise ArgumentError,
              "expected #{inspect(RootModulatedParams)} in :machine_params, got #{inspect(other)}"

      :error ->
        raise ArgumentError, "missing :machine_params for #{inspect(__MODULE__)}"
    end
  end

  defp note_frame(note, at_mbeat, _sample_context) when at_mbeat < note.delay_mbeats do
    %{
      note_name: note.note_name,
      octave: note.octave,
      midi_note: note.midi_note,
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
       when at_mbeat > note.delay_mbeats + note.adsr.total_mbeats do
    %{
      note_name: note.note_name,
      octave: note.octave,
      midi_note: note.midi_note,
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

  defp note_frame(note, at_mbeat, sample_context) do
    local_elapsed_mbeats = at_mbeat - note.delay_mbeats
    local_elapsed_ms = SampleContext.mbeats_to_ms(sample_context, local_elapsed_mbeats)

    %{
      note_name: note.note_name,
      octave: note.octave,
      midi_note: note.midi_note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
      phase: NoteShape.phase_at(note.adsr, local_elapsed_mbeats),
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.adsr.total_mbeats,
      pressure:
        NoteShape.pressure(note.adsr, note.phase_offset, local_elapsed_mbeats, local_elapsed_ms)
        |> clamp_7bit(),
      bend: NoteShape.bend(note.adsr, note.phase_offset, local_elapsed_ms, local_elapsed_mbeats),
      slide:
        NoteShape.slide(
          note.adsr,
          note.phase_offset,
          note.emphasis,
          local_elapsed_ms,
          local_elapsed_mbeats
        )
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

  defp snap_mbeats(mbeats, mbeats_per_frame),
    do: round(mbeats / mbeats_per_frame) * mbeats_per_frame

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end

defimpl Mensch.Machine, for: Mensch.Machines.RootModulated do
  alias Mensch.Machines.RootModulated

  def id(_machine), do: RootModulated.id()

  def controls(%RootModulated{}), do: %{}

  def build_frame_sequence(
        %RootModulated{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    RootModulated.build_frame_sequence(
      chord_spec,
      sample_context,
      timeline_context,
      Keyword.put(opts, :machine_params, params)
    )
  end
end
