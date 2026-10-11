defmodule Mensch.Machines.RootNote do
  @moduledoc """
  Machine that plays only the harmonic root note for the full entry duration.

  The generated pitch is based on chord identity (`root` + `octave`) and is
  intentionally independent from chord inversion. `octave_offset` transposes the
  root by whole octaves.

  RootNote always uses a zero pressure baseline. Any non-zero pressure must come
  from the configured note-modulation strategy.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machine.Pipeline
  alias Mensch.Machine.RenderContextCommon
  alias Mensch.Machines.RootNoteParams

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
  @note_off_velocity 77

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :root_note

  def params_module, do: RootNoteParams

  def default_params, do: RootNoteParams.default()

  def default_modulation_strategy, do: default_params().modulation_strategy

  @spec new(RootNoteParams.t()) :: t()
  def new(%RootNoteParams{} = params), do: %__MODULE__{params: params}

  def controls do
    params = default_params()

    %{
      octave_offset: params.octave_offset,
      velocity: params.velocity,
      pressure: params.pressure
    }
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
        note_on_velocity: 0,
        note_off_velocity: 0,
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
  @spec assign_note_velocities(t(), [NotePlanItem.t()], RenderContext.t()) :: [NotePlanItem.t()]
  def assign_note_velocities(
        %__MODULE__{},
        note_plan,
        %RenderContext{params: %RootNoteParams{velocity: velocity}}
      )
      when is_list(note_plan) do
    Enum.map(note_plan, fn %NotePlanItem{} = note ->
      %NotePlanItem{note | note_on_velocity: velocity, note_off_velocity: @note_off_velocity}
    end)
  end

  @impl Pipeline
  @spec modulation_strategy(t(), RenderContext.t()) :: struct()
  def modulation_strategy(%__MODULE__{params: %RootNoteParams{} = params}, %RenderContext{}),
    do: params.modulation_strategy

  @doc false
  @spec normalize_params(RootNoteParams.t()) :: RootNoteParams.t()
  def normalize_params(%RootNoteParams{} = params) do
    defaults = default_params() |> Map.from_struct()
    current = params |> Map.from_struct()

    defaults
    |> Map.merge(current)
    |> then(&struct!(RootNoteParams, &1))
    |> RootNoteParams.validate_modulation_strategy!()
  end

  defp root_midi_note!(%ChordSpec{} = chord_spec, octave_offset) when is_integer(octave_offset) do
    chord_spec = normalize_chord_spec(chord_spec)

    midi_note =
      ChordSpec.midi_note_number(chord_spec.root, chord_spec.octave) + octave_offset * 12

    if midi_note < 0 or midi_note > 127 do
      raise ArgumentError,
            "root_note produced out-of-range midi note #{midi_note} from root #{inspect(chord_spec.root)} octave #{inspect(chord_spec.octave)} with octave_offset #{inspect(octave_offset)}"
    end

    midi_note
  end

  defp normalize_chord_spec(%ChordSpec{voicing: nil} = chord_spec) do
    chord_spec
    |> Map.from_struct()
    |> ChordSpec.new!()
  end

  defp normalize_chord_spec(%ChordSpec{} = chord_spec), do: chord_spec
end

defimpl Mensch.Machine, for: Mensch.Machines.RootNote do
  alias Mensch.Machines.RootNote

  def id(_machine), do: RootNote.id()

  def controls(%RootNote{params: params}) do
    %{
      octave_offset: params.octave_offset,
      velocity: params.velocity,
      pressure: params.pressure,
      note_modulation_strategy: inspect(params.modulation_strategy.__struct__)
    }
  end

  def build_frame_sequence(
        %RootNote{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    normalized_params = RootNote.normalize_params(params)

    Mensch.Machine.Pipeline.build_frame_sequence(
      RootNote,
      %RootNote{params: normalized_params},
      chord_spec,
      sample_context,
      timeline_context,
      opts
    )
  end
end
