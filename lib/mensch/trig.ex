defmodule Mensch.Trig do
  @moduledoc """
  A single step slot on a track.

  A trig is either empty (`type: nil`), a Note Trig (starts a musical
  event), or a Lock Trig (changes parameters of the currently sounding
  performance without starting a new event). A trig may carry parameter
  locks that override the track's Machine defaults; it does not duplicate
  every Machine parameter.
  """

  alias Mensch.ParameterResolver

  defstruct [:step, type: nil, locks: %{}]

  @type trig_type :: :note | :lock
  @type t :: %__MODULE__{
          step: pos_integer(),
          type: trig_type() | nil,
          locks: %{atom() => term()}
        }

  @doc "Builds an empty trig for the given step (1-based)."
  @spec new(pos_integer()) :: t()
  def new(step) when is_integer(step) and step > 0 do
    %__MODULE__{step: step, type: nil, locks: %{}}
  end

  @doc """
  Applies a Program Mode tap: tapping a trig of the selected type empties
  it; any other tap sets the trig to the selected type (resetting locks).
  """
  @spec apply_program_tap(t(), trig_type()) :: t()
  def apply_program_tap(%__MODULE__{type: type} = trig, selected_type) do
    if type == selected_type do
      %{trig | type: nil, locks: %{}}
    else
      %{trig | type: selected_type, locks: %{}}
    end
  end

  @doc "Locks `key` at `value`."
  @spec lock(t(), atom(), term()) :: t()
  def lock(%__MODULE__{locks: locks} = trig, key, value) do
    %{trig | locks: Map.put(locks, key, value)}
  end

  @doc "Clears the lock for `key`, reverting it to the Machine default."
  @spec clear_lock(t(), atom()) :: t()
  def clear_lock(%__MODULE__{locks: locks} = trig, key) do
    %{trig | locks: Map.delete(locks, key)}
  end

  @doc "Nudges an existing lock's value up or down. No-op if not locked."
  @spec adjust_lock(t(), atom(), :up | :down) :: t()
  def adjust_lock(%__MODULE__{locks: locks} = trig, key, direction) do
    case Map.fetch(locks, key) do
      {:ok, value} -> %{trig | locks: Map.put(locks, key, ParameterResolver.adjust(value, key, direction))}
      :error -> trig
    end
  end
end
