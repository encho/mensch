defmodule Mensch.Harmony.Progression.Middleware.ReorderChordProgression do
  @moduledoc """
  Reorders a progression's chords by index.

  The provided order is normalized against the current chord count:
  - invalid/out-of-range indices are ignored
  - duplicates are removed (first occurrence wins)
  - missing indices are appended at the end in natural order
  """

  alias Mensch.Harmony.ChordProgression

  @type opts :: [order: [integer()]]

  @spec middleware(opts()) :: (ChordProgression.t() ->
                                 {:ok, ChordProgression.t()} | {:error, term()})
  def middleware(opts \\ []) when is_list(opts) do
    order = Keyword.get(opts, :order, [])

    fn progression ->
      reorder(progression, order)
    end
  end

  defp reorder(%ChordProgression{} = progression, order) when is_list(order) do
    chords = progression.chords
    count = length(chords)
    normalized_order = normalize_order(order, count)
    reordered_chords = Enum.map(normalized_order, &Enum.at(chords, &1))

    {:ok, %{progression | chords: reordered_chords}}
  end

  defp reorder(%ChordProgression{} = progression, _order) do
    {:ok, progression}
  end

  defp reorder(_progression, _order), do: {:error, :invalid_progression}

  @spec normalize_order([integer()], non_neg_integer()) :: [non_neg_integer()]
  def normalize_order(order, count) when is_list(order) and is_integer(count) and count >= 0 do
    valid =
      order
      |> Enum.filter(&(is_integer(&1) and &1 >= 0 and &1 < count))
      |> Enum.reduce([], fn index, acc -> if index in acc, do: acc, else: acc ++ [index] end)

    missing =
      0
      |> Stream.iterate(&(&1 + 1))
      |> Enum.take(count)
      |> Enum.reject(&(&1 in valid))

    valid ++ missing
  end

  def normalize_order(_order, count) when is_integer(count) and count >= 0 do
    if count > 0 do
      Enum.to_list(0..(count - 1))
    else
      []
    end
  end
end
