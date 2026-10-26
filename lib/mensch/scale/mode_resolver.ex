defmodule Mensch.Scale.ModeResolver do
  @moduledoc """
  Resolves modal interval patterns via generic rotation.
  """

  alias Mensch.Scale.ScaleRegistry

  @spec resolve(atom(), pos_integer() | nil) :: {:ok, map()} | {:error, term()}
  def resolve(family_id, mode) when is_atom(family_id) do
    with {:ok, entry} <- ScaleRegistry.fetch(family_id) do
      do_resolve(entry, mode)
    end
  end

  defp do_resolve(entry, nil) do
    if modal_family?(entry) do
      resolve_mode(entry, 1)
    else
      {:ok, %{name: entry.name, mode: nil, intervals: entry.intervals}}
    end
  end

  defp do_resolve(entry, mode) when is_integer(mode) and mode > 0 do
    if modal_family?(entry) do
      resolve_mode(entry, mode)
    else
      {:ok, %{name: entry.name, mode: nil, intervals: entry.intervals}}
    end
  end

  defp do_resolve(_entry, _mode), do: {:error, :invalid_mode}

  defp resolve_mode(entry, mode) do
    intervals = entry.intervals
    size = length(intervals)

    if mode >= 1 and mode <= size do
      offset = Enum.at(intervals, mode - 1)

      rotated =
        intervals
        |> Enum.drop(mode - 1)
        |> Kernel.++(Enum.take(intervals, mode - 1))
        |> Enum.map(&rem(&1 - offset + 12, 12))
        |> Enum.uniq()
        |> Enum.sort()

      name =
        case Map.get(entry.mode_names || %{}, mode) do
          nil -> "Mode #{mode} of #{entry.name}"
          mode_name -> mode_name
        end

      {:ok, %{name: name, mode: mode, intervals: rotated}}
    else
      {:error, {:invalid_mode_number, mode, size}}
    end
  end

  defp modal_family?(entry), do: is_map(entry) and is_map(Map.get(entry, :mode_names))
end
