defmodule Mensch.Harmony.ResolverTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.ForeignBass
  alias Mensch.Harmony.ChordSpec.Voicing
  alias Mensch.Harmony.Resolver

  test "defaults preserve close voicing behavior when optional fields are omitted" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 0
      })

    assert Resolver.resolve(spec) == [48, 52, 55, 59]
  end

  test "applies inversion before voicing" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 1,
        voicing: %Voicing{type: :close, center_note: 60}
      })

    steps = Resolver.resolve_steps(spec)

    assert steps.resolved_chord_tones == [48, 52, 55, 59]
    assert steps.inverted_chord_tones == [52, 55, 59, 60]
    assert steps.voiced_chord_tones == [52, 55, 59, 60]
    assert steps.foreign_bass_note == nil
    assert steps.final_notes == [52, 55, 59, 60]
  end

  test "open voicing keeps inversion bass and opens upper voices" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 1,
        voicing: %Voicing{type: :open, center_note: 60}
      })

    # Inversion 1 gives [E, G, B, C]; open voicing raises every 2nd upper voice.
    assert Resolver.resolve(spec) == [52, 55, 60, 71]
  end

  test "major 6 quality resolves with added sixth" do
    spec =
      ChordSpec.new!(%{
        root: :g,
        quality: :maj6,
        octave: 3,
        inversion: 0,
        voicing: %Voicing{type: :close, center_note: 60}
      })

    assert Resolver.resolve(spec) == [55, 59, 62, 64]
  end

  test "voice_count expansion with auto doubling is deterministic" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 0,
        voicing: %Voicing{type: :close, center_note: 60, voice_count: 6, doubling: :auto}
      })

    assert Resolver.resolve(spec) == [48, 52, 55, 59, 60, 67]
  end

  test "fails hard when foreign bass is not foreign" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 0,
        foreign_bass: %ForeignBass{pitch_class: :e, mode: :relative, octave: 0}
      })

    assert_raise ArgumentError, ~r/not foreign/, fn ->
      Resolver.resolve(spec)
    end
  end

  test "relative foreign bass offset 0 auto-shifts one octave lower when needed" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 0,
        voicing: %Voicing{type: :close, center_note: 60},
        foreign_bass: %ForeignBass{pitch_class: :b_flat, mode: :relative, octave: 0}
      })

    notes = Resolver.resolve(spec)

    assert notes == [46, 48, 52, 55, 59]
  end

  test "relative foreign bass offset tracks lowest voiced chord octave" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 1,
        voicing: %Voicing{type: :open, center_note: 60},
        foreign_bass: %ForeignBass{pitch_class: :f_sharp, mode: :relative, octave: 1}
      })

    notes = Resolver.resolve(spec)

    assert hd(notes) == 42
    assert notes == [42, 52, 55, 60, 71]
  end

  test "fails hard when constraints are unsatisfiable" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 3,
        voicing: %Voicing{type: :open, center_note: 84, range_min: 48, range_max: 52}
      })

    assert_raise ArgumentError, ~r/unsatisfiable voicing constraints/, fn ->
      Resolver.resolve(spec)
    end
  end

  test "fails hard when explicit foreign bass is above or equal to lowest chord voice" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 0,
        voicing: %Voicing{type: :close, center_note: 60},
        foreign_bass: %ForeignBass{pitch_class: :f_sharp, mode: :absolute, octave: 4}
      })

    assert_raise ArgumentError, ~r/must be below the lowest voiced chord tone/, fn ->
      Resolver.resolve(spec)
    end
  end

  test "per-step centered mode can wrap back after enough inversions" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 4,
        voicing: %Voicing{
          type: :close,
          center_note: 60,
          inversion_tracking_mode: :per_step_centered
        }
      })

    assert Resolver.resolve(spec) == [48, 52, 55, 59]
  end

  test "anchor-then-wander mode keeps inversion drift without re-centering each step" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 4,
        voicing: %Voicing{
          type: :close,
          center_note: 60,
          inversion_tracking_mode: :anchor_then_wander
        }
      })

    assert Resolver.resolve(spec) == [60, 64, 67, 71]
  end

  test "sequence export follows inversion path from zero to target" do
    spec =
      ChordSpec.new!(%{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 4,
        voicing: %Voicing{
          type: :close,
          center_note: 60,
          inversion_tracking_mode: :anchor_then_wander
        }
      })

    sequence = Resolver.resolve_inversion_sequence(spec)

    assert Enum.map(sequence, & &1.inversion) == [0, 1, 2, 3, 4]

    assert Enum.map(sequence, & &1.final_notes) == [
             [48, 52, 55, 59],
             [52, 55, 59, 60],
             [55, 59, 60, 64],
             [59, 60, 64, 67],
             [60, 64, 67, 71]
           ]
  end
end
