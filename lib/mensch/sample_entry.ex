defmodule Mensch.SampleEntry do
  @moduledoc """
  Typed sample entry containing harmonic content, timing, and machine.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.TimelineContext

  @enforce_keys [:chord_spec, :timeline_context, :machine]
  defstruct [:chord_spec, :timeline_context, :machine]

  @type t :: %__MODULE__{
          chord_spec: ChordSpec.t(),
          timeline_context: TimelineContext.t(),
          machine: struct()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    entry = struct(__MODULE__, attrs)

    cond do
      not match?(%ChordSpec{}, entry.chord_spec) ->
        {:error, {:invalid_chord_spec, entry.chord_spec}}

      not match?(%TimelineContext{}, entry.timeline_context) ->
        {:error, {:invalid_timeline_context, entry.timeline_context}}

      not is_map(entry.machine) or not Map.has_key?(entry.machine, :__struct__) ->
        {:error, {:invalid_machine, entry.machine}}

      true ->
        {:ok, entry}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, entry} -> entry
      {:error, reason} -> raise ArgumentError, "invalid sample entry: #{inspect(reason)}"
    end
  end
end
