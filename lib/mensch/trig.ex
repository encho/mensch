defmodule Mensch.Trig do
  @moduledoc """
  A single step slot on a track.

  A trig is either empty (`type: nil`), a Note Trig (starts a musical
  event), or a Lock Trig (changes parameters of the currently sounding
  performance without starting a new event). A trig may carry parameter
  locks that override the track's Harmonic Context or Machine defaults,
  namespaced by which one they belong to; it does not duplicate every
  parameter.
  """

  alias Mensch.ParameterResolver

  defstruct [:step, type: nil, locks: %{}]

  @type trig_type :: :note | :lock
  @type lock_namespace :: :harmonic_context | :machine
  @type t :: %__MODULE__{
          step: pos_integer(),
          type: trig_type() | nil,
          locks: %{optional(lock_namespace()) => %{optional(atom()) => term()}}
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

  @doc "Locks `key` at `value`, within `namespace`."
  @spec lock(t(), lock_namespace(), atom(), term()) :: t()
  def lock(%__MODULE__{locks: locks} = trig, namespace, key, value) do
    namespace_locks = Map.get(locks, namespace, %{})
    %{trig | locks: Map.put(locks, namespace, Map.put(namespace_locks, key, value))}
  end

  @doc "Clears the lock for `key` within `namespace`, reverting it to the Track default."
  @spec clear_lock(t(), lock_namespace(), atom()) :: t()
  def clear_lock(%__MODULE__{locks: locks} = trig, namespace, key) do
    case Map.fetch(locks, namespace) do
      {:ok, namespace_locks} ->
        namespace_locks = Map.delete(namespace_locks, key)

        locks =
          if namespace_locks == %{} do
            Map.delete(locks, namespace)
          else
            Map.put(locks, namespace, namespace_locks)
          end

        %{trig | locks: locks}

      :error ->
        trig
    end
  end

  @doc "Nudges an existing lock's value up or down. No-op if not locked."
  @spec adjust_lock(t(), lock_namespace(), atom(), :up | :down) :: t()
  def adjust_lock(%__MODULE__{locks: locks} = trig, namespace, key, direction) do
    with {:ok, namespace_locks} <- Map.fetch(locks, namespace),
         {:ok, value} <- Map.fetch(namespace_locks, key) do
      new_value = ParameterResolver.adjust(namespace, key, value, direction)
      %{trig | locks: Map.put(locks, namespace, Map.put(namespace_locks, key, new_value))}
    else
      :error -> trig
    end
  end

  @doc "Returns whether `key` is locked within `namespace`."
  @spec locked?(t(), lock_namespace(), atom()) :: boolean()
  def locked?(%__MODULE__{locks: locks}, namespace, key) do
    locks |> Map.get(namespace, %{}) |> Map.has_key?(key)
  end
end
