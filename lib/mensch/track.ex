defmodule Mensch.Track do
  @moduledoc """
  A track holds 16 trigs and a machine that defines their default
  musical parameters.
  """

  alias Mensch.Machine
  alias Mensch.ParameterResolver
  alias Mensch.Trig

  defstruct [:id, :name, machine: nil, trigs: []]

  @type t :: %__MODULE__{
          id: pos_integer(),
          name: String.t(),
          machine: Machine.t(),
          trigs: [Trig.t()]
        }

  @trig_count 16

  @doc "Builds a track with #{@trig_count} empty trigs and default machine params."
  @spec new(pos_integer(), String.t()) :: t()
  def new(id, name) do
    trigs = for step <- 1..@trig_count, do: Trig.new(step)
    %__MODULE__{id: id, name: name, machine: Machine.new(), trigs: trigs}
  end

  @doc "Returns the trig at the given step, or nil if not found."
  @spec trig_at(t(), pos_integer()) :: Trig.t() | nil
  def trig_at(%__MODULE__{trigs: trigs}, step) do
    Enum.find(trigs, &(&1.step == step))
  end

  @doc "Applies a Program Mode tap at `step` using the given selected trig type."
  @spec apply_program_tap(t(), pos_integer(), Trig.trig_type()) :: t()
  def apply_program_tap(%__MODULE__{} = track, step, selected_type) do
    update_trig(track, step, &Trig.apply_program_tap(&1, selected_type))
  end

  @doc "Locks `key` on the trig at `step`, starting from the current machine default."
  @spec lock_param(t(), pos_integer(), atom()) :: t()
  def lock_param(%__MODULE__{machine: machine} = track, step, key) do
    default_value = machine |> Map.from_struct() |> Map.fetch!(key)
    update_trig(track, step, &Trig.lock(&1, key, default_value))
  end

  @doc "Clears the lock for `key` on the trig at `step`."
  @spec clear_lock(t(), pos_integer(), atom()) :: t()
  def clear_lock(%__MODULE__{} = track, step, key) do
    update_trig(track, step, &Trig.clear_lock(&1, key))
  end

  @doc "Nudges the locked value for `key` on the trig at `step` up or down."
  @spec adjust_lock(t(), pos_integer(), atom(), :up | :down) :: t()
  def adjust_lock(%__MODULE__{} = track, step, key, direction) do
    update_trig(track, step, &Trig.adjust_lock(&1, key, direction))
  end

  @doc "Effective params for the trig at `step`: machine defaults overridden by locks."
  @spec effective_params(t(), pos_integer()) :: ParameterResolver.params()
  def effective_params(%__MODULE__{machine: machine} = track, step) do
    ParameterResolver.resolve(machine, trig_at(track, step))
  end

  defp update_trig(%__MODULE__{trigs: trigs} = track, step, fun) do
    trigs =
      Enum.map(trigs, fn
        %Trig{step: ^step} = trig -> fun.(trig)
        trig -> trig
      end)

    %{track | trigs: trigs}
  end
end
