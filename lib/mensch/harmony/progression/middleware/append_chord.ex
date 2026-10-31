defmodule Mensch.Harmony.Progression.Middleware.AppendChord do
  @moduledoc """
  Appends a single chord to the end of a progression.
  """

  alias Mensch.Harmony.ChordProgression
  alias Mensch.Harmony.ChordSpec

  @type opts :: [chord_spec: ChordSpec.t()]

  @spec middleware(opts()) :: (ChordProgression.t() ->
                                 {:ok, ChordProgression.t()} | {:error, term()})
  def middleware(opts \\ []) when is_list(opts) do
    chord_spec = Keyword.get(opts, :chord_spec)

    fn progression ->
      append_chord(progression, chord_spec)
    end
  end

  defp append_chord(%ChordProgression{} = progression, %ChordSpec{} = chord_spec) do
    {:ok, %{progression | chords: progression.chords ++ [chord_spec]}}
  end

  defp append_chord(%ChordProgression{}, _chord_spec), do: {:error, :invalid_chord_spec}
  defp append_chord(_progression, _chord_spec), do: {:error, :invalid_progression}
end
