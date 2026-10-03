defmodule Mensch.Machines.Strum do
  @moduledoc """
  Machine that strums all notes of a chord together for the full chord duration.

  All chord tones start at chord start and release at chord end.

  Modulation model:

  - note planning is machine-owned
  - note modulation is delegated to a strategy
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machine.Pipeline
  alias Mensch.Machine.RenderContextCommon
  alias Mensch.Machines.StrumParams

  defmodule RenderContext do
    @moduledoc false

    alias Mensch.Machine.RenderContextCommon
    alias Mensch.Machines.StrumParams

    @enforce_keys [:params, :common]
    defstruct [:params, :common]

    @type t :: %__MODULE__{
            params: StrumParams.t(),
            common: RenderContextCommon.t()
          }
  end

  @type t :: %__MODULE__{params: StrumParams.t()}

  @behaviour Pipeline
  @note_off_velocity 77

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :strum

  def params_module, do: StrumParams

  def default_params, do: StrumParams.default()

  def default_modulation_strategy, do: default_params().modulation_strategy

  @spec new(StrumParams.t()) :: t()
  def new(%StrumParams{} = params), do: %__MODULE__{params: params}

  def controls do
    params = default_params()

    %{
      velocity: params.velocity
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
    chord_notes = ChordSpec.to_midi_notes(chord_spec)

    chord_notes
    |> Enum.with_index()
    |> Enum.map(fn {midi_note, note_instance_id} ->
      {note_name, octave} = ChordSpec.note_name(midi_note)

      NotePlanItem.new(%{
        note_name: note_name,
        octave: octave,
        midi_note: midi_note,
        channel: nil,
        note_on_velocity: 0,
        note_off_velocity: 0,
        machine_id: id(),
        chord_instance_id: 0,
        note_instance_id: note_instance_id,
        degree_index: note_instance_id,
        harmonic_tags: harmonic_tags_for_degree(note_instance_id),
        role_tags: [],
        machine_note_tags: [],
        start_mbeat: render_context.common.chord_start_mbeat,
        duration_mbeats: render_context.common.chord_duration_mbeats
      })
    end)
  end

  @impl Pipeline
  @spec assign_note_velocities(t(), [NotePlanItem.t()], RenderContext.t()) :: [NotePlanItem.t()]
  def assign_note_velocities(
        %__MODULE__{},
        note_plan,
        %RenderContext{params: %StrumParams{velocity: velocity}}
      )
      when is_list(note_plan) do
    Enum.map(note_plan, fn %NotePlanItem{} = note ->
      %NotePlanItem{note | note_on_velocity: velocity, note_off_velocity: @note_off_velocity}
    end)
  end

  @impl Pipeline
  @spec modulation_strategy(t(), RenderContext.t()) :: struct()
  def modulation_strategy(%__MODULE__{params: %StrumParams{} = params}, %RenderContext{}),
    do: params.modulation_strategy

  @doc false
  @spec normalize_params(StrumParams.t()) :: StrumParams.t()
  def normalize_params(%StrumParams{} = params) do
    defaults = default_params() |> Map.from_struct()
    current = params |> Map.from_struct()

    defaults
    |> Map.merge(current)
    |> then(&struct!(StrumParams, &1))
    |> StrumParams.validate_modulation_strategy!()
  end

  defp harmonic_tags_for_degree(0), do: [:root]
  defp harmonic_tags_for_degree(1), do: [:third]
  defp harmonic_tags_for_degree(2), do: [:fifth]
  defp harmonic_tags_for_degree(3), do: [:seventh]
  defp harmonic_tags_for_degree(_), do: [:tension]
end

defimpl Mensch.Machine, for: Mensch.Machines.Strum do
  alias Mensch.Machines.Strum

  def id(_machine), do: Strum.id()

  def controls(%Strum{params: params}) do
    %{
      velocity: params.velocity,
      note_modulation_strategy: inspect(params.modulation_strategy.__struct__)
    }
  end

  def build_frame_sequence(
        %Strum{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    normalized_params = Strum.normalize_params(params)

    Mensch.Machine.Pipeline.build_frame_sequence(
      Strum,
      %Strum{params: normalized_params},
      chord_spec,
      sample_context,
      timeline_context,
      opts
    )
  end
end
