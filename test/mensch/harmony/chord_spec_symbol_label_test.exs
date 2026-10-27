defmodule Mensch.Harmony.ChordSpecSymbolLabelTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.ChordSpec

  test "does not render slash when bass equals root" do
    spec =
      ChordSpec.new!(%{
        harmonic_identity: %ChordSpec.HarmonicIdentity{
          root: :c,
          quality: :maj11,
          foreign_bass: :c
        },
        octave: 3,
        inversion: 0
      })

    assert ChordSpec.symbol_label(spec) == "Cmaj11"
  end

  test "renders slash when bass differs from root" do
    spec =
      ChordSpec.new!(%{
        harmonic_identity: %ChordSpec.HarmonicIdentity{
          root: :c,
          quality: :maj11,
          foreign_bass: :e
        },
        octave: 3,
        inversion: 0
      })

    assert ChordSpec.symbol_label(spec) == "Cmaj11/E"
  end
end
