defmodule Mensch.Harmony.Progression.Source.CreateEmptyProgression do
  @moduledoc """
  Source that creates an empty progression with no chords.
  """

  alias Mensch.Harmony.ChordProgression

  @spec source(keyword()) :: (-> {:ok, ChordProgression.t()} | {:error, term()})
  def source(_opts \\ []) do
    fn ->
      {:ok,
       %ChordProgression{
         name: "Empty Progression",
         description: "Starts with no chords.",
         chords: []
       }}
    end
  end
end
