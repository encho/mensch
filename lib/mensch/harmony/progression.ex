defmodule Mensch.Harmony.Progression do
  @moduledoc """
  Progression pipeline utilities.

  A progression is represented as `%Mensch.Harmony.ChordProgression{}`.

  Sources are zero-arity functions that create the initial progression.
  Transforms are functions that receive a progression and return either:

  * `{:ok, progression}`
  * `{:error, reason}`
  """

  alias Mensch.Harmony.ChordProgression

  @type progression :: ChordProgression.t()
  @type result :: {:ok, progression()} | {:error, term()}

  @type middleware_result :: result()
  @type middleware :: (progression() -> middleware_result())

  @type source :: (-> result())
  @type transform :: (progression() -> result())

  @spec run(progression(), [middleware()]) :: middleware_result()
  def run(%ChordProgression{} = progression, middlewares) when is_list(middlewares) do
    Enum.reduce_while(middlewares, {:ok, progression}, fn middleware, {:ok, acc} ->
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
    with {:ok, initial_progression} <- source.(),
         {:ok, progression} <- run_transforms(initial_progression, transforms) do
      {:ok, progression}
    else
      {:error, {:transform_failed, _index, _reason} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:source_failed, reason}}
    end
  end

  defp run_transforms(%ChordProgression{} = progression, transforms) do
    transforms
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, progression}, fn {transform, index}, {:ok, acc} ->
      case transform.(acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, {:transform_failed, index, reason}}}
      end
    end)
  end
end
