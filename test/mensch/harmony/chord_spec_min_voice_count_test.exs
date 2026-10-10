defmodule Mensch.Harmony.ChordSpecMinVoiceCountTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.Voicing

  test "persists min_voice_count derived from chord quality" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj11,
        octave: 3,
        inversion: 0
      })

    assert spec.min_voice_count == 6
    assert ChordSpec.min_voice_count(spec) == 6
  end

  test "allows nil voice_count as auto/min behavior" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 0,
        voicing: %Voicing{voice_count: nil}
      })

    assert spec.voicing.voice_count == nil
    assert spec.min_voice_count == 4
  end

  test "rejects explicit voice_count below chord minimum" do
    assert {:error, {:invalid_voice_count_below_min, {3, 4}}} =
             ChordSpec.new(%{
               root: :c,
               quality: :maj7,
               octave: 3,
               inversion: 0,
               voicing: %Voicing{voice_count: 3}
             })
  end
end
