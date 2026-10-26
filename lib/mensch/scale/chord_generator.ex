defmodule Mensch.Scale.ChordGenerator do
  @moduledoc """
  Facade for scale-driven chord generation.

  This module is additive and independent from legacy harmony/progression
  generators.
  """

  alias Mensch.Scale.ChordStrategy
  alias Mensch.Scale.ChordStrategy.Quartal
  alias Mensch.Scale.ChordStrategy.Quintal
  alias Mensch.Scale.ChordStrategy.Tertian
  alias Mensch.Scale.ScaleSpec

  @strategies [Tertian, Quartal, Quintal]

  @type strategy_id :: atom()

  @spec strategy_options() :: [map()]
  def strategy_options do
    Enum.map(@strategies, fn strategy ->
      %{
        id: strategy.id(),
        label: strategy.label(),
        shapes: strategy.shapes()
      }
    end)
  end

  @spec generate(ScaleSpec.t(), pos_integer(), keyword()) ::
          {:ok, ChordStrategy.generated_chord()} | {:error, term()}
  def generate(scale_spec, degree, opts \\ [])

  def generate(%ScaleSpec{} = scale_spec, degree, opts) do
    with {:ok, strategy} <- resolve_strategy(Keyword.get(opts, :strategy, :tertian)) do
      strategy.generate(scale_spec, degree, opts)
    end
  end

  def generate(_scale_spec, _degree, _opts), do: {:error, :invalid_scale_spec}

  @spec strategy_shapes(strategy_id()) :: {:ok, [ChordStrategy.chord_shape()]} | {:error, term()}
  def strategy_shapes(strategy_id) when is_atom(strategy_id) do
    with {:ok, strategy} <- resolve_strategy(strategy_id) do
      {:ok, strategy.shapes()}
    end
  end

  def strategy_shapes(_strategy_id), do: {:error, :invalid_strategy}

  defp resolve_strategy(strategy_id) when is_atom(strategy_id) do
    case Enum.find(@strategies, &(&1.id() == strategy_id)) do
      nil -> {:error, {:unknown_strategy, strategy_id}}
      strategy -> {:ok, strategy}
    end
  end

  defp resolve_strategy(_strategy_id), do: {:error, :invalid_strategy}
end
