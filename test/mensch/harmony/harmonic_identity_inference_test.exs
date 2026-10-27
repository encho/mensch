defmodule Mensch.Harmony.HarmonicIdentityInferenceTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.HarmonicIdentityInference
  alias Mensch.Scale

  test "returns all matches sorted by descending quality" do
    matches = HarmonicIdentityInference.infer([60, 64, 67])

    assert length(matches) > 10

    qualities = Enum.map(matches, & &1.quality)
    assert qualities == Enum.sort(qualities, :desc)

    top = hd(matches)
    assert top.harmonic_identity.root == :c
    assert top.harmonic_identity.quality == :maj
    assert top.quality >= 90.0
  end

  test "sets bass_pitch_class only when bass is foreign for the candidate" do
    matches = HarmonicIdentityInference.infer([60, 64, 67], bass_pitch_class: :g)

    top = hd(matches)
    assert top.harmonic_identity.root == :c
    assert top.harmonic_identity.quality == :maj
    assert top.harmonic_identity.foreign_bass == nil

    matches_with_foreign_bass =
      HarmonicIdentityInference.infer([60, 64, 67], bass_pitch_class: :f_sharp)

    c_major =
      Enum.find(matches_with_foreign_bass, fn match ->
        match.harmonic_identity.root == :c and match.harmonic_identity.quality == :maj
      end)

    assert c_major.harmonic_identity.foreign_bass == :f_sharp
  end

  test "uses optional scale spec in scoring" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    matches = HarmonicIdentityInference.infer([60, 64, 67], scale_spec: scale_spec)
    top = hd(matches)

    assert top.harmonic_identity.root == :c
    assert top.harmonic_identity.quality == :maj
    assert top.quality >= 90.0
  end

  test "quintal sonority still resolves into ranked tertian approximations" do
    matches = HarmonicIdentityInference.infer([60, 67, 62])

    assert length(matches) > 0
    assert Enum.all?(matches, &is_float(&1.quality))
  end

  test "priors prefer cm7 over ebmaj6 slash reinterpretation in c dorian degree 1 seventh" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 2)

    # C Dorian degree 1 seventh from tertian strategy: C Eb G Bb
    matches =
      HarmonicIdentityInference.infer([60, 63, 67, 70],
        scale_spec: scale_spec,
        bass_pitch_class: :c,
        preferred_root_pitch_class: 0,
        preferred_strategy: :tertian,
        preferred_shape: :seventh,
        preferred_degree: 1
      )

    top = hd(matches)

    assert top.harmonic_identity.root == :c
    assert top.harmonic_identity.quality == :min7
  end

  test "scale context drives enharmonic spelling in harmonic identity structs" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 7)

    expectations = [
      {1, :c, :dim},
      {2, :d_flat, :maj},
      {3, :e_flat, :min},
      {4, :f, :min},
      {5, :g_flat, :maj},
      {6, :a_flat, :maj},
      {7, :b_flat, :min}
    ]

    Enum.each(expectations, fn {degree, expected_root, expected_quality} ->
      {:ok, chord} = Scale.generate_chord(scale_spec, degree, strategy: :tertian, shape: :triad)

      top =
        HarmonicIdentityInference.infer(chord.pitch_classes,
          scale_spec: scale_spec,
          bass_pitch_class: expected_root,
          preferred_root_pitch_class: chord.root_pitch_class,
          preferred_strategy: :tertian,
          preferred_shape: :triad,
          preferred_degree: degree
        )
        |> List.first()

      assert top.harmonic_identity.root == expected_root
      assert top.harmonic_identity.quality == expected_quality
    end)
  end

  test "strict spelling mode picks f_sharp root in eb harmonic minor mode 6 degree 2 ninth" do
    {:ok, scale_spec} = Scale.build_scale(:e_flat, :harmonic_minor, 6)
    {:ok, chord} = Scale.generate_chord(scale_spec, 2, strategy: :tertian, shape: :ninth)

    top =
      HarmonicIdentityInference.infer(chord.pitch_classes,
        scale_spec: scale_spec,
        spelling_mode: :strict,
        bass_pitch_class: :f_sharp,
        preferred_root_pitch_class: chord.root_pitch_class,
        preferred_strategy: :tertian,
        preferred_shape: :ninth,
        preferred_degree: 2
      )
      |> List.first()

    assert top.harmonic_identity.root == :f_sharp
    assert top.harmonic_identity.quality == :dim7_flat9
  end

  test "direct resolver match is always first when available" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)
    {:ok, chord} = Scale.generate_chord(scale_spec, 1, strategy: :tertian, shape: :triad)

    [top | _rest] =
      HarmonicIdentityInference.infer(chord.pitch_classes,
        scale_spec: scale_spec,
        spelling_mode: :practical,
        bass_pitch_class: :c,
        preferred_root_pitch_class: chord.root_pitch_class,
        preferred_strategy: :tertian,
        preferred_shape: :triad,
        preferred_degree: 1
      )

    assert top.source == :direct
    assert top.harmonic_identity.root == :c
    assert top.harmonic_identity.quality == :maj
  end

  test "eleventh case uses direct source with preserved generated root" do
    {:ok, scale_spec} = Scale.build_scale(:d, :melodic_minor, 6)
    {:ok, chord} = Scale.generate_chord(scale_spec, 4, strategy: :tertian, shape: :eleventh)

    [top | _rest] =
      HarmonicIdentityInference.infer(chord.pitch_classes,
        scale_spec: scale_spec,
        spelling_mode: :practical,
        bass_pitch_class: :g,
        preferred_root_pitch_class: chord.root_pitch_class,
        preferred_strategy: :tertian,
        preferred_shape: :eleventh,
        preferred_degree: 4
      )

    assert top.source == :direct
    assert top.harmonic_identity.root == :g
  end

  test "c ionian degree-3 ninth resolves direct-first as e min7_flat9" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)
    {:ok, chord} = Scale.generate_chord(scale_spec, 3, strategy: :tertian, shape: :ninth)

    [top | _rest] =
      HarmonicIdentityInference.infer(chord.pitch_classes,
        scale_spec: scale_spec,
        spelling_mode: :practical,
        bass_pitch_class: :e,
        preferred_root_pitch_class: chord.root_pitch_class,
        preferred_strategy: :tertian,
        preferred_shape: :ninth,
        preferred_degree: 3
      )

    assert top.source == :direct
    assert top.harmonic_identity.root == :e
    assert top.harmonic_identity.quality == :min7_flat9
  end

  test "c ionian degree-5 eleventh resolves direct-first as g dom11" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)
    {:ok, chord} = Scale.generate_chord(scale_spec, 5, strategy: :tertian, shape: :eleventh)

    [top | _rest] =
      HarmonicIdentityInference.infer(chord.pitch_classes,
        scale_spec: scale_spec,
        spelling_mode: :practical,
        bass_pitch_class: :g,
        preferred_root_pitch_class: chord.root_pitch_class,
        preferred_strategy: :tertian,
        preferred_shape: :eleventh,
        preferred_degree: 5
      )

    assert top.source == :direct
    assert top.harmonic_identity.root == :g
    assert top.harmonic_identity.quality == :dom11
  end

  test "c ionian degree-1 thirteenth resolves direct-first as c maj13" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)
    {:ok, chord} = Scale.generate_chord(scale_spec, 1, strategy: :tertian, shape: :thirteenth)

    [top | _rest] =
      HarmonicIdentityInference.infer(chord.pitch_classes,
        scale_spec: scale_spec,
        spelling_mode: :practical,
        bass_pitch_class: :c,
        preferred_root_pitch_class: chord.root_pitch_class,
        preferred_strategy: :tertian,
        preferred_shape: :thirteenth,
        preferred_degree: 1
      )

    assert top.source == :direct
    assert top.harmonic_identity.root == :c
    assert top.harmonic_identity.quality == :maj13
  end
end
