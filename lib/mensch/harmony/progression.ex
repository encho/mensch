defmodule Mensch.Harmony.Progression do
  @moduledoc """
  Progression pipeline utilities.

  A progression is represented as a list of `%Mensch.Harmony.ChordSpec{}`.

  Supports two execution styles:

  * `run/2`: legacy middleware chain, starting from an explicit initial list.
  * `run_with_source/2`: source + transform pipeline.

  Sources are zero-arity functions that create the initial chord list.
  Transforms are functions that receive a chord list and return either:

  * `{:ok, chord_list}`
  * `{:error, reason}`
  """

  alias Mensch.Harmony.ChordSpec

  @type chord_list :: [ChordSpec.t()]
  @type result :: {:ok, chord_list()} | {:error, term()}

  @type middleware_result :: result()
  @type middleware :: (chord_list() -> middleware_result())

  @type source :: (-> result())
  @type transform :: (chord_list() -> result())

  @spec run(chord_list(), [middleware()]) :: middleware_result()
  def run(chord_list, middlewares) when is_list(chord_list) and is_list(middlewares) do
    Enum.reduce_while(middlewares, {:ok, chord_list}, fn middleware, {:ok, acc} ->
      case middleware.(acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Runs a source + transform pipeline.

  Source failures are wrapped as `{:error, {:source_failed, reason}}`.
  Transform failures are wrapped as `{:error, {:transform_failed, index, reason}}`.
  """
  @spec run_with_source(source(), [transform()]) :: result()
  def run_with_source(source, transforms)
      when is_function(source, 0) and is_list(transforms) do
    with {:ok, initial_chords} <- source.(),
         {:ok, chords} <- run_transforms(initial_chords, transforms) do
      {:ok, chords}
    else
      {:error, {:transform_failed, _index, _reason} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:source_failed, reason}}
    end
  end

  defp run_transforms(chords, transforms) do
    transforms
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, chords}, fn {transform, index}, {:ok, acc} ->
      case transform.(acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, {:transform_failed, index, reason}}}
      end
    end)
  end
end
