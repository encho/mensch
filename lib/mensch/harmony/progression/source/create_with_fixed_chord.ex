defmodule Mensch.Harmony.Progression.Source.CreateWithFixedChord do
  @moduledoc """
  Test source that creates a progression by repeating one fixed chord.
  """

  alias Mensch.Harmony.ChordProgression
  alias Mensch.Harmony.ChordSpec

  @type opts :: [
          root: ChordSpec.pitch_class(),
          quality: ChordSpec.quality(),
          count: pos_integer(),
          octave: integer(),
          inversion: integer()
        ]

  @spec source(opts()) :: (-> {:ok, ChordProgression.t()} | {:error, term()})
  def source(opts \\ []) when is_list(opts) do
    fn ->
      root = Keyword.get(opts, :root, :c)
      quality = Keyword.get(opts, :quality, :maj)
      count = Keyword.get(opts, :count, 7)
      octave = Keyword.get(opts, :octave, 3)
      inversion = Keyword.get(opts, :inversion, 0)

      with :ok <- validate_count(count) do
        chord =
          ChordSpec.new!(%{
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: root, quality: quality},
            octave: octave,
            inversion: inversion
          })

        {:ok,
         %ChordProgression{
           name: "Fixed Chord Progression",
           description: "Repeats a single fixed chord #{count} times.",
           chords: List.duplicate(chord, count)
         }}
      end
    end
  end

  defp validate_count(count) when is_integer(count) and count > 0, do: :ok
  defp validate_count(_count), do: {:error, :invalid_count}
end
