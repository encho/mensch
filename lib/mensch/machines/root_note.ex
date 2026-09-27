defmodule Mensch.Machines.RootNote do
  @moduledoc """
  Machine that plays only the harmonic root note for the full entry duration.

  The generated pitch is based on chord identity (`root` + `octave`) and is
  intentionally independent from chord inversion. `octave_offset` transposes the
  root by whole octaves.

  RootNote always uses a zero pressure baseline. Any non-zero pressure must come
  from `lfo_pressure` modulation.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.NoteFrame
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machine.Pipeline
  alias Mensch.Machine.RenderContextCommon
  alias Mensch.Machines.RootNoteParams
  alias Mensch.NewModulation
  alias Mensch.NewModulation.Lfo
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  defmodule RenderContext do
    @moduledoc false

    alias Mensch.Machine.RenderContextCommon
    alias Mensch.Machines.RootNoteParams

    @enforce_keys [:params, :common]
    defstruct [:params, :common]

    @type t :: %__MODULE__{
            params: RootNoteParams.t(),
            common: RenderContextCommon.t()
          }
  end

  @type t :: %__MODULE__{params: RootNoteParams.t()}

  @behaviour Pipeline

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
      pressure: params.pressure,
      lfo_pressure: params.lfo_pressure
    }
  end

  def build_frame_sequence(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %RootNoteParams{} = params = machine_params!(opts) |> hydrate_params()

    Pipeline.build_frame_sequence(
      __MODULE__,
      %__MODULE__{params: params},
      chord_spec,
      sample_context,
      timeline_context,
      opts
    )
  end

  @impl Pipeline
  @spec build_render_context(t(), RenderContextCommon.common_fields()) ::
          RenderContext.t()
  def build_render_context(
        %__MODULE__{params: params},
        %RenderContextCommon{} = common
      ) do
    struct!(RenderContext, %{params: params, common: common})
  end

  @impl Pipeline
  @spec build_note_plan(t(), ChordSpec.t(), RenderContext.t()) :: [NotePlanItem.t()]
  def build_note_plan(%__MODULE__{}, %ChordSpec{} = chord_spec, %RenderContext{} = render_context) do
    root_midi_note = root_midi_note!(chord_spec, render_context.params.octave_offset)

    {note_name, octave} = ChordSpec.note_name(root_midi_note)

    [
      NotePlanItem.new(%{
        note_name: note_name,
        octave: octave,
        midi_note: root_midi_note,
        channel: nil,
        note_on_velocity: render_context.params.velocity,
        machine_id: id(),
        chord_instance_id: 0,
        note_instance_id: 0,
        degree_index: 0,
        harmonic_tags: [:root],
        role_tags: [],
        machine_note_tags: [],
        start_mbeat: render_context.common.chord_start_mbeat,
        duration_mbeats: render_context.common.chord_duration_mbeats
      })
    ]
  end

  @impl Pipeline
  @spec render_note_frame(NotePlanItem.t(), non_neg_integer(), RenderContext.t()) :: map()
  def render_note_frame(note, at_mbeat, %RenderContext{} = render_context) do
    local_elapsed_mbeats = at_mbeat - note.start_mbeat
    phase = if(local_elapsed_mbeats < note.duration_mbeats, do: :sustain, else: :release)

    %SampleContext{} = sample_context = render_context.common.sample_context
    absolute_chord_start_mbeat = render_context.common.absolute_chord_start_mbeat
    pressure_lfo = render_context.params.lfo_pressure.lfo
    pressure_lfo_mode = render_context.params.lfo_pressure.mode

    pressure_lfo_value =
      Lfo.evaluate(
        pressure_lfo,
        at_mbeat,
        sample_context,
        absolute_chord_start_mbeat,
        local_elapsed_mbeats
      )

    modulated_pressure =
      NewModulation.apply_to_pressure(0, pressure_lfo_value, pressure_lfo_mode)

    NoteFrame.from_note_plan_item(note, %{
      phase: phase,
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.duration_mbeats,
      pressure: modulated_pressure,
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

    # Merge defaults first, then canonicalize lfo_pressure so rendering code can
    # rely on a validated %{lfo: ..., mode: ...} shape.
    defaults
    |> Map.merge(current)
    |> Map.update!(
      :lfo_pressure,
      &NewModulation.normalize_lfo_pressure!(&1, "root_note lfo_pressure")
    )
    |> then(&struct!(RootNoteParams, &1))
  end

  @doc false
  @spec normalize_lfo_pressure(map()) :: NewModulation.lfo_pressure()
  # Public wrapper used by protocol controls/1 to expose normalized machine params.
  def normalize_lfo_pressure(lfo_pressure) do
    NewModulation.normalize_lfo_pressure!(lfo_pressure, "root_note lfo_pressure")
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
end

defimpl Mensch.Machine, for: Mensch.Machines.RootNote do
  alias Mensch.Machines.RootNote

  def id(_machine), do: RootNote.id()

  def controls(%RootNote{params: params}) do
    lfo_pressure = RootNote.normalize_lfo_pressure(Map.get(params, :lfo_pressure))

    %{
      octave_offset: params.octave_offset,
      velocity: params.velocity,
      pressure: params.pressure,
      lfo_pressure: lfo_pressure
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
