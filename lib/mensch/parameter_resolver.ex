defmodule Mensch.ParameterResolver do
  @moduledoc """
  Resolves effective musical parameters for a trig by merging Machine
  defaults with the trig's parameter locks. Locks win; no lock means
  the value is inherited from the machine.
  """

  alias Mensch.Machine
  alias Mensch.Trig

  @type params :: %{atom() => term()}

  @doc "Effective params for a trig: machine defaults overridden by locks."
  @spec resolve(Machine.t(), Trig.t()) :: params()
  def resolve(%Machine{} = machine, %Trig{locks: locks}) do
    Map.merge(Map.from_struct(machine), locks)
  end

  @steps %{expression: 0.05, pressure: 0.05, duration: {:beats, 0.25}, release: {:beats, 0.25}}

  @doc "Nudges a locked value up or down for the given parameter key."
  @spec adjust(term(), atom(), :up | :down) :: term()
  def adjust(value, key, direction) when key in [:expression, :pressure] do
    step = Map.fetch!(@steps, key)
    delta = if direction == :up, do: step, else: -step

    value
    |> Kernel.+(delta)
    |> max(0.0)
    |> min(1.0)
    |> Float.round(2)
  end

  def adjust({:beats, beats}, key, direction) when key in [:duration, :release] do
    {:beats, step} = Map.fetch!(@steps, key)
    delta = if direction == :up, do: step, else: -step
    new_beats = max(beats + delta, step)
    {:beats, Float.round(new_beats * 1.0, 2)}
  end
end
