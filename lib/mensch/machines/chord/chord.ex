defmodule Mensch.Machines.Chord do
  @moduledoc """
  Machine that plays all notes of a chord together for the full chord duration.

  All chord tones start at chord start and release at chord end.

  Modulation model:

  - note planning is machine-owned
  - note modulation is delegated to a strategy
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machine.Pipeline
  alias Mensch.Machine.RenderContextCommon
  alias Mensch.Machines.ChordParams

  defmodule RenderContext do
    @moduledoc false

    alias Mensch.Machine.RenderContextCommon
    alias Mensch.Machines.ChordParams

    @enforce_keys [:params, :common]
    defstruct [:params, :common]

    @type t :: %__MODULE__{
            params: ChordParams.t(),
            common: RenderContextCommon.t()
          }
  end

  @type t :: %__MODULE__{params: ChordParams.t()}

  @behaviour Pipeline

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :chord

  def params_module, do: ChordParams

  def default_params, do: ChordParams.default()

  def default_modulation_strategy, do: default_params().modulation_strategy

  @spec new(ChordParams.t()) :: t()
  def new(%ChordParams{} = params), do: %__MODULE__{params: params}

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
        note_on_velocity: render_context.params.velocity,
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
  @spec modulation_strategy(t(), RenderContext.t()) :: struct()
  def modulation_strategy(%__MODULE__{params: %ChordParams{} = params}, %RenderContext{}),
    do: params.modulation_strategy

  @doc false
  @spec normalize_params(ChordParams.t()) :: ChordParams.t()
  def normalize_params(%ChordParams{} = params) do
    defaults = default_params() |> Map.from_struct()
    current = params |> Map.from_struct()

    defaults
    |> Map.merge(current)
    |> then(&struct!(ChordParams, &1))
    |> ChordParams.validate_modulation_strategy!()
  end

  defp harmonic_tags_for_degree(0), do: [:root]
  defp harmonic_tags_for_degree(1), do: [:third]
  defp harmonic_tags_for_degree(2), do: [:fifth]
  defp harmonic_tags_for_degree(3), do: [:seventh]
  defp harmonic_tags_for_degree(_), do: [:tension]
end

defimpl Mensch.Machine, for: Mensch.Machines.Chord do
  alias Mensch.Machines.Chord

  def id(_machine), do: Chord.id()

  def controls(%Chord{params: params}) do
    %{
      velocity: params.velocity,
      note_modulation_strategy: inspect(params.modulation_strategy.__struct__)
    }
  end

  def build_frame_sequence(
        %Chord{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    normalized_params = Chord.normalize_params(params)

    Mensch.Machine.Pipeline.build_frame_sequence(
      Chord,
      %Chord{params: normalized_params},
      chord_spec,
      sample_context,
      timeline_context,
      opts
    )
  end
end
