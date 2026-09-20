defmodule Mensch.Machines.RootNote do
  @moduledoc """
  Machine that plays only the harmonic root note for the full entry duration.

  The generated pitch is based on chord identity (`root` + `octave`) and is
  intentionally independent from chord inversion. `octave_offset` transposes the
  root by whole octaves.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.MachineFrameSequence
  alias Mensch.Machine.NoteFrame
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machines.RootNoteParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @type t :: %__MODULE__{params: RootNoteParams.t()}

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :root_note

  def params_module, do: RootNoteParams

  def default_params, do: RootNoteParams.default()

  @spec new(RootNoteParams.t()) :: t()
  def new(%RootNoteParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  def controls do
    params = default_params()

    %{
      octave_offset: params.octave_offset,
      velocity: params.velocity,
      pressure: params.pressure
    }
  end

  def build_frame_sequence(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %RootNoteParams{} = params = machine_params!(opts) |> hydrate_params()

    frame_mbeats = SampleContext.frame_units(sample_context)

    chord_duration_mbeats =
      timeline_context
      |> TimelineContext.duration_mbeats()
      |> snap_mbeats(frame_mbeats)

    sample_start_mbeat =
      timeline_context
      |> TimelineContext.start_mbeat(sample_context)
      |> snap_mbeats(frame_mbeats)

    root_midi_note = root_midi_note!(chord_spec, params.octave_offset)

    {note_name, octave} = ChordSpec.note_name(root_midi_note)

    note_plan_item =
      NotePlanItem.new(%{
        note_name: note_name,
        octave: octave,
        midi_note: root_midi_note,
        channel: nil,
        note_on_velocity: params.velocity,
        machine_id: id(),
        chord_instance_id: 0,
        note_instance_id: 0,
        degree_index: 0,
        delay_mbeats: sample_start_mbeat
      })

    note_frame_stream =
      render_note_frame_stream(
        note_plan_item,
        chord_duration_mbeats,
        frame_mbeats,
        params.pressure
      )

    max_note_end_mbeats = note_plan_item.delay_mbeats + chord_duration_mbeats
    assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_duration_mbeats)

    %MachineFrameSequence{
      frames: stitch_note_frame_stream(note_frame_stream, chord_duration_mbeats, frame_mbeats)
    }
  end

  defp render_note_frame_stream(note, duration_mbeats, frame_mbeats, pressure) do
    note_end_mbeat = min(note.delay_mbeats + duration_mbeats, duration_mbeats)

    for at_mbeat <- note.delay_mbeats..note_end_mbeat//frame_mbeats do
      %{at_mbeat: at_mbeat, note: note_frame(note, at_mbeat, duration_mbeats, pressure)}
    end
  end

  defp stitch_note_frame_stream(note_frame_stream, duration_mbeats, frame_mbeats) do
    notes_by_mbeat =
      note_frame_stream
      |> Enum.group_by(& &1.at_mbeat, & &1.note)

    for at_mbeat <- 0..duration_mbeats//frame_mbeats do
      %{at_mbeat: at_mbeat, notes: Map.get(notes_by_mbeat, at_mbeat, [])}
    end
  end

  defp note_frame(note, at_mbeat, duration_mbeats, pressure) do
    local_elapsed_mbeats = at_mbeat - note.delay_mbeats
    phase = if(local_elapsed_mbeats < duration_mbeats, do: :sustain, else: :release)

    NoteFrame.from_note_plan_item(note, %{
      phase: phase,
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == duration_mbeats,
      pressure: clamp_7bit(pressure),
      bend: 0.0,
      slide: 0
    })
  end

  defp machine_params!(opts) do
    case Keyword.fetch(opts, :machine_params) do
      {:ok, %RootNoteParams{} = params} ->
        params

      {:ok, other} ->
        raise ArgumentError,
              "expected #{inspect(RootNoteParams)} in :machine_params, got #{inspect(other)}"

      :error ->
        raise ArgumentError, "missing :machine_params for #{inspect(__MODULE__)}"
    end
  end

  defp hydrate_params(%RootNoteParams{} = params) do
    defaults = default_params() |> Map.from_struct()
    current = params |> Map.from_struct()

    defaults
    |> Map.merge(current)
    |> then(&struct!(RootNoteParams, &1))
  end

  defp root_midi_note!(%ChordSpec{} = chord_spec, octave_offset) when is_integer(octave_offset) do
    midi_note = midi_note_number(chord_spec.root, chord_spec.octave) + octave_offset * 12

    if midi_note < 0 or midi_note > 127 do
      raise ArgumentError,
            "root_note produced out-of-range midi note #{midi_note} from root #{inspect(chord_spec.root)} octave #{inspect(chord_spec.octave)} with octave_offset #{inspect(octave_offset)}"
    end

    midi_note
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

  defp assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_duration_mbeats)
       when max_note_end_mbeats == chord_duration_mbeats,
       do: :ok

  defp assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_duration_mbeats) do
    raise ArgumentError,
          "root_note invariant violated: last note ends at #{max_note_end_mbeats}, expected #{chord_duration_mbeats}"
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end

defimpl Mensch.Machine, for: Mensch.Machines.RootNote do
  alias Mensch.Machines.RootNote

  def id(_machine), do: RootNote.id()

  def controls(%RootNote{params: params}) do
    %{
      octave_offset: params.octave_offset,
      velocity: params.velocity,
      pressure: params.pressure
    }
  end

  def build_frame_sequence(
        %RootNote{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    RootNote.build_frame_sequence(
      chord_spec,
      sample_context,
      timeline_context,
      Keyword.put(opts, :machine_params, params)
    )
  end
end
