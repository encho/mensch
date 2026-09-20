defmodule Mensch.NewModulation.LfoGroup do
  @moduledoc """
  Ordered composition of LFO terms.

  The group is evaluated left-to-right starting from `initial`, then applying
  each operation in sequence.
  """

  alias Mensch.NewModulation.LfoCurve
  alias Mensch.NewModulation.LfoRamp
  alias Mensch.NewModulation.LfoSaw

  @type operation_name :: :add | :multiply
  @type lfo_term :: LfoCurve.t() | LfoSaw.t() | LfoRamp.t() | t()
  @type operation :: {operation_name(), lfo_term()}

  @type t :: %__MODULE__{
          initial: lfo_term(),
          operations: [operation()]
        }

  @enforce_keys [:initial]
  defstruct [:initial, operations: []]

  @spec default() :: t()
  def default do
    %__MODULE__{initial: LfoCurve.default(), operations: []}
  end

  @spec normalize!(t() | map() | nil, keyword()) :: t()
  def normalize!(lfo_group, opts \\ [])

  def normalize!(nil, _opts), do: default()

  def normalize!(%__MODULE__{} = lfo_group, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo group")

    %__MODULE__{
      initial: normalize_term!(lfo_group.initial, "#{field_name}.initial"),
      operations: normalize_operations!(lfo_group.operations, field_name)
    }
  end

  def normalize!(lfo_group, opts) when is_map(lfo_group) do
    attrs = symbolize_map_keys(lfo_group)

    default()
    |> Map.from_struct()
    |> Map.merge(Map.drop(attrs, [:__struct__]))
    |> then(&struct!(__MODULE__, &1))
    |> normalize!(opts)
  end

  def normalize!(other, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo group")
    raise ArgumentError, "#{field_name} must be #{inspect(__MODULE__)}, got: #{inspect(other)}"
  end

  @spec normalize_term!(any(), String.t()) :: lfo_term()
  def normalize_term!(%LfoCurve{} = lfo_curve, field_name) do
    LfoCurve.normalize!(lfo_curve, field_name: field_name)
  end

  def normalize_term!(%LfoSaw{} = lfo_saw, field_name) do
    LfoSaw.normalize!(lfo_saw, field_name: field_name)
  end

  def normalize_term!(%LfoRamp{} = lfo_ramp, field_name) do
    LfoRamp.normalize!(lfo_ramp, field_name: field_name)
  end

  def normalize_term!(%__MODULE__{} = lfo_group, field_name) do
    normalize!(lfo_group, field_name: field_name)
  end

  def normalize_term!(term, field_name) when is_map(term) do
    attrs = symbolize_map_keys(term)

    cond do
      Map.has_key?(attrs, :initial) -> normalize!(attrs, field_name: field_name)
      ramp_term_map?(attrs) -> LfoRamp.normalize!(attrs, field_name: field_name)
      saw_term_map?(attrs) -> LfoSaw.normalize!(attrs, field_name: field_name)
      true -> LfoCurve.normalize!(attrs, field_name: field_name)
    end
  end

  def normalize_term!(other, field_name) do
    raise ArgumentError,
          "#{field_name} must be #{inspect(LfoCurve)}, #{inspect(LfoSaw)}, #{inspect(LfoRamp)}, or #{inspect(__MODULE__)}, got: #{inspect(other)}"
  end

  defp ramp_term_map?(attrs) do
    Map.has_key?(attrs, :span_mbeats) or Map.has_key?(attrs, :start_value) or
      Map.has_key?(attrs, :end_value) or
      Map.get(attrs, :interpolation_function) in [:linear, :ease_in, :ease_out, :ease_in_out]
  end

  defp saw_term_map?(attrs) do
    Map.has_key?(attrs, :drop_phase) or Map.get(attrs, :curve) in [:saw, :saw_up, :saw_down]
  end

  defp normalize_operations!(operations, field_name) when is_list(operations) do
    Enum.map(operations, fn
      {operation, term} when operation in [:add, :multiply] ->
        {operation, normalize_term!(term, "#{field_name}.operations")}

      other ->
        raise ArgumentError,
              "#{field_name}.operations entries must be {:add | :multiply, lfo}, got: #{inspect(other)}"
    end)
  end

  defp normalize_operations!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.operations must be a list, got: #{inspect(other)}"
  end

  defp symbolize_map_keys(map) do
    map
    |> Enum.map(fn
      {"initial", value} -> {:initial, value}
      {"operations", value} -> {:operations, value}
      {key, value} -> {key, value}
    end)
    |> Map.new()
  end
end

defimpl Mensch.NewModulation.Lfo, for: Mensch.NewModulation.LfoGroup do
  alias Mensch.NewModulation.Lfo
  alias Mensch.NewModulation.LfoGroup

  def evaluate(
        %LfoGroup{} = lfo_group,
        at_mbeat,
        sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      ) do
    lfo_group = LfoGroup.normalize!(lfo_group, field_name: "lfo group")

    initial_value =
      Lfo.evaluate(
        lfo_group.initial,
        at_mbeat,
        sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      )

    Enum.reduce(lfo_group.operations, initial_value, fn
      {:add, term}, value ->
        value +
          Lfo.evaluate(
            term,
            at_mbeat,
            sample_context,
            entry_start_mbeat_abs,
            note_local_mbeat
          )

      {:multiply, term}, value ->
        value *
          Lfo.evaluate(
            term,
            at_mbeat,
            sample_context,
            entry_start_mbeat_abs,
            note_local_mbeat
          )
    end)
  end
end
