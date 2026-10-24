defmodule Mensch.Harmony.DiatonicChordBuilderTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.DiatonicChordBuilder

  test "builds major scale triad by degree" do
    assert {:ok, spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 2,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.root(spec) == :d
    assert ChordSpec.quality(spec) == :min
    assert spec.octave == 3
    assert spec.inversion == 0
  end

  test "defaults chord kind to triad when octave and inversion are provided" do
    assert {:ok, spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 5,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.quality(spec) == :maj
  end

  test "builds major scale sevenths" do
    assert {:ok, spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 5,
               chord_kind: :seventh,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.root(spec) == :g
    assert ChordSpec.quality(spec) == :dom7
    assert ChordSpec.tones(spec) == ["1", "3", "5", "b7"]
  end

  test "builds natural minor triad degree two as diminished" do
    assert {:ok, spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :natural_minor}, 2,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.root(spec) == :d
    assert ChordSpec.quality(spec) == :dim
  end

  test "builds harmonic minor fifth as major triad" do
    assert {:ok, spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :harmonic_minor}, 5,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.root(spec) == :g
    assert ChordSpec.quality(spec) == :maj
  end

  test "builds harmonic minor first seventh as min_maj7 quality" do
    assert {:ok, spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :harmonic_minor}, 1,
               chord_kind: :seventh,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.root(spec) == :c
    assert ChordSpec.quality(spec) == :min_maj7
    assert ChordSpec.tones(spec) == ["1", "b3", "5", "7"]
  end

  test "builds harmonic minor third seventh as maj7_sharp5 quality" do
    assert {:ok, spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :harmonic_minor}, 3,
               chord_kind: :seventh,
               octave: 4,
               inversion: 1
             )

    assert ChordSpec.root(spec) == :d_sharp
    assert ChordSpec.quality(spec) == :maj7_sharp5
    assert ChordSpec.tones(spec) == ["1", "3", "#5", "7"]
  end

  test "supports added and extended forms" do
    assert {:ok, add6_spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 1,
               chord_kind: :add6,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.quality(add6_spec) == :maj6

    assert {:ok, six_nine_spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 4,
               chord_kind: :six_nine,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.quality(six_nine_spec) == :six_nine

    assert {:ok, ninth_spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 5,
               chord_kind: :ninth,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.quality(ninth_spec) == :dom9

    assert {:ok, eleventh_spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :natural_minor}, 4,
               chord_kind: :eleventh,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.quality(eleventh_spec) == :min11

    assert {:ok, thirteenth_spec} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :harmonic_minor}, 5,
               chord_kind: :thirteenth,
               octave: 3,
               inversion: 0
             )

    assert ChordSpec.quality(thirteenth_spec) == :dom13
  end

  test "returns unsupported error when chord form is unavailable for degree" do
    assert {:error,
            {:unsupported_chord_kind_for_degree,
             %{mode: :major, chord_kind: :thirteenth, degree: 1}}} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 1,
               chord_kind: :thirteenth,
               octave: 3,
               inversion: 0
             )
  end

  test "requires caller to pass octave and inversion" do
    assert {:error, {:missing_opt, :octave}} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 1, inversion: 0)

    assert {:error, {:missing_opt, :inversion}} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 1, octave: 3)
  end

  test "returns error for invalid degree" do
    assert {:error, {:invalid_degree, 0}} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :major}, 0)
  end

  test "returns error for invalid mode" do
    assert {:error, {:invalid_mode, :dorian}} =
             DiatonicChordBuilder.build(%{tonic: :c, mode: :dorian}, 1)
  end

  test "build! raises for invalid request" do
    assert_raise ArgumentError, fn ->
      DiatonicChordBuilder.build!(%{tonic: :c, mode: :major}, 12)
    end
  end
end
