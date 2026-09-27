defmodule Mensch.NewModulation.LfoConstant do
  @moduledoc """
  Constant modulation source.

  Always returns the configured numeric `value`.
  """

  @type t :: %__MODULE__{value: float()}

  defstruct value: 0.0

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec normalize!(t() | map() | nil, keyword()) :: t()
  def normalize!(lfo_constant, opts \\ [])

  def normalize!(nil, _opts), do: default()

  def normalize!(%__MODULE__{} = lfo_constant, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo constant")

    %__MODULE__{
      value: normalize_value!(lfo_constant.value, field_name)
    }
  end

  def normalize!(lfo_constant, opts) when is_map(lfo_constant) do
    lfo_constant
    |> symbolize_map_keys()
    |> then(fn attrs -> struct!(__MODULE__, Map.merge(Map.from_struct(default()), attrs)) end)
    |> normalize!(opts)
  end

  def normalize!(other, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo constant")
    raise ArgumentError, "#{field_name} must be #{inspect(__MODULE__)}, got: #{inspect(other)}"
  end

  defp normalize_value!(value, _field_name) when is_integer(value), do: value * 1.0
  defp normalize_value!(value, _field_name) when is_float(value), do: value

  defp normalize_value!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.value must be a number, got: #{inspect(other)}"
  end

  defp symbolize_map_keys(map) do
    map
    |> Enum.map(fn
      {"value", value} -> {:value, value}
      pair -> pair
    end)
    |> Map.new()
  end
end

defimpl Mensch.NewModulation.Lfo, for: Mensch.NewModulation.LfoConstant do
  alias Mensch.NewModulation.LfoConstant

  def evaluate(
        %LfoConstant{} = lfo_constant,
        _at_mbeat,
        _sample_context,
        _absolute_chord_start_mbeat,
        _note_local_mbeat
      ) do
    lfo_constant
    |> LfoConstant.normalize!(field_name: "lfo constant")
    |> Map.fetch!(:value)
  end
end
