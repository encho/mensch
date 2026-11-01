defmodule Mensch.Harmony.Progression.Middleware.DeleteChordsFromProgression do
  @moduledoc """
  Deletes selected chord indices from a progression.

  The provided indices are normalized against the current chord count:
  - invalid/out-of-range indices are ignored
  - duplicates are removed
  """

  alias Mensch.Harmony.ChordProgression

  @type opts :: [deleted_indices: [integer()]]

  @spec middleware(opts()) :: (ChordProgression.t() ->
                                 {:ok, ChordProgression.t()} | {:error, term()})
  def middleware(opts \\ []) when is_list(opts) do
    deleted_indices = Keyword.get(opts, :deleted_indices, [])

    fn progression ->
      delete_chords(progression, deleted_indices)
    end
  end

  defp delete_chords(%ChordProgression{} = progression, deleted_indices)
       when is_list(deleted_indices) do
    normalized_deleted_indices =
      normalize_deleted_indices(deleted_indices, length(progression.chords))

    kept_chords =
      progression.chords
      |> Enum.with_index()
      |> Enum.reject(fn {_chord, index} -> index in normalized_deleted_indices end)
      |> Enum.map(fn {chord, _index} -> chord end)

    {:ok, %{progression | chords: kept_chords}}
  end

  defp delete_chords(%ChordProgression{} = progression, _deleted_indices) do
    {:ok, progression}
  end

  defp delete_chords(_progression, _deleted_indices), do: {:error, :invalid_progression}

  @spec normalize_deleted_indices([integer()], non_neg_integer()) :: [non_neg_integer()]
  def normalize_deleted_indices(indices, chord_count)
      when is_list(indices) and is_integer(chord_count) and chord_count >= 0 do
    indices
    |> Enum.filter(&(is_integer(&1) and &1 >= 0 and &1 < chord_count))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def normalize_deleted_indices(_indices, _chord_count), do: []
end
