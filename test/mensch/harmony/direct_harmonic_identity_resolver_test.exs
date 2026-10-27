defmodule Mensch.Harmony.DirectHarmonicIdentityResolverTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.DirectHarmonicIdentityResolver
  alias Mensch.Scale

  test "resolves direct identity for tertian triads in C major" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    {:ok, chord} = Scale.generate_chord(scale_spec, 2, strategy: :tertian, shape: :triad)

    assert {:ok, identity} =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :tertian,
               shape: :triad,
               degree: 2
             )

    assert identity.root == :d
    assert identity.quality == :min
    assert identity.foreign_bass == nil
  end

  test "uses contextual spelling for roots" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 7)

    {:ok, chord} = Scale.generate_chord(scale_spec, 2, strategy: :tertian, shape: :triad)

    assert {:ok, identity} =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :tertian,
               shape: :triad,
               degree: 2
             )

    assert identity.root == :d_flat
    assert identity.quality == :maj
  end

  test "returns unknown for non-tertian strategies" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    {:ok, chord} = Scale.generate_chord(scale_spec, 1, strategy: :quartal, shape: :triad)

    assert :unknown =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :quartal,
               shape: :triad,
               degree: 1
             )
  end

  test "falls back to root-preserving best fit for eleventh shape" do
    {:ok, scale_spec} = Scale.build_scale(:d, :melodic_minor, 6)
    {:ok, chord} = Scale.generate_chord(scale_spec, 4, strategy: :tertian, shape: :eleventh)

    assert {:ok, identity} =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :tertian,
               shape: :eleventh,
               degree: 4
             )

    assert identity.root == :g
    assert identity.foreign_bass == nil
    assert identity.quality in [:maj11, :min11, :dom13, :min7_add11]
  end

  test "falls back to root-preserving best fit for add6 shape" do
    {:ok, scale_spec} = Scale.build_scale(:f, :melodic_minor, 7)
    {:ok, chord} = Scale.generate_chord(scale_spec, 1, strategy: :tertian, shape: :add6)

    assert {:ok, identity} =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :tertian,
               shape: :add6,
               degree: 1,
               spelling_mode: :strict
             )

    assert identity.root == :f
    assert identity.foreign_bass == nil
    assert identity.quality in [:maj6, :min6, :maj7_sharp5, :min_maj7, :dom7, :half_dim]
  end

  test "falls back to root-preserving best fit for six_nine shape" do
    {:ok, scale_spec} = Scale.build_scale(:a, :harmonic_major, 6)
    {:ok, chord} = Scale.generate_chord(scale_spec, 1, strategy: :tertian, shape: :six_nine)

    assert {:ok, identity} =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :tertian,
               shape: :six_nine,
               degree: 1
             )

    assert identity.root == :a
    assert identity.foreign_bass == nil
    assert identity.quality == :six_nine
  end

  test "resolves c ionian degree-3 ninth deterministically as e min7_flat9" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)
    {:ok, chord} = Scale.generate_chord(scale_spec, 3, strategy: :tertian, shape: :ninth)

    assert {:ok, identity} =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :tertian,
               shape: :ninth,
               degree: 3,
               spelling_mode: :practical
             )

    assert identity.root == :e
    assert identity.quality == :min7_flat9
    assert identity.foreign_bass == nil
  end

  test "resolves c ionian degree-5 eleventh deterministically as g dom11" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)
    {:ok, chord} = Scale.generate_chord(scale_spec, 5, strategy: :tertian, shape: :eleventh)

    assert {:ok, identity} =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :tertian,
               shape: :eleventh,
               degree: 5,
               spelling_mode: :practical
             )

    assert identity.root == :g
    assert identity.quality == :dom11
    assert identity.foreign_bass == nil
  end

  test "resolves c ionian degree-1 thirteenth deterministically as c maj13" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)
    {:ok, chord} = Scale.generate_chord(scale_spec, 1, strategy: :tertian, shape: :thirteenth)

    assert {:ok, identity} =
             DirectHarmonicIdentityResolver.resolve(scale_spec, chord,
               strategy: :tertian,
               shape: :thirteenth,
               degree: 1,
               spelling_mode: :practical
             )

    assert identity.root == :c
    assert identity.quality == :maj13
    assert identity.foreign_bass == nil
  end
end
