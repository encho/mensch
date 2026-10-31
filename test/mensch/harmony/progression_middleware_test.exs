defmodule Mensch.Harmony.ProgressionMiddlewareTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordProgression
  alias Mensch.Harmony.Progression
  alias Mensch.Harmony.Progression.Middleware.EnsureBassAscending
  alias Mensch.Harmony.Progression.Middleware.TransposeAll
  alias Mensch.Harmony.Progression.Source.CreateWithFixedChord

  alias Mensch.Harmony.Progression.Source.CreateWithScaleGeneratedHarmonicIdentities,
    as: ScaleGeneratedSource

  alias Mensch.Harmony.Resolver

  test "scale-generated source generates chords for requested degrees" do
    source =
      ScaleGeneratedSource.source(
        degrees: [2, 5, 1],
        scale: %{tonic: :c, family: :major, mode: 1},
        strategy: :tertian,
        shape: :triad,
        spelling_mode: :practical,
        render_defaults: %{octave: 3, inversion: 0}
      )

    assert {:ok, progression} = source.()
    chords = progression.chords
    assert length(chords) == 3

    assert Enum.map(chords, &ChordSpec.quality/1) == [:min, :maj, :maj]
  end

  test "scale-generated source validates degrees against selected scale size" do
    source =
      ScaleGeneratedSource.source(
        degrees: [1, 8],
        scale: %{tonic: :c, family: :major, mode: 1},
        strategy: :tertian,
        shape: :triad,
        spelling_mode: :practical,
        render_defaults: %{octave: 3, inversion: 0}
      )

    assert {:error, {:invalid_degrees_for_scale, 7}} = source.()
  end

  test "scale-generated source creates chords using scale-chord-lab identity path" do
    source =
      ScaleGeneratedSource.source(
        degrees: [2, 5, 1],
        scale: %{tonic: :c, family: :major, mode: 1},
        strategy: :tertian,
        shape: :triad,
        spelling_mode: :practical,
        render_defaults: %{octave: 3, inversion: 0}
      )

    assert {:ok, progression} = source.()
    chords = progression.chords
    assert length(chords) == 3
    assert Enum.map(chords, &ChordSpec.quality/1) == [:min, :maj, :maj]
  end

  test "scale-generated source validates scale map shape" do
    source =
      ScaleGeneratedSource.source(
        degrees: [1],
        scale: %{tonic: :c, mode: 1},
        strategy: :tertian,
        shape: :triad,
        render_defaults: %{octave: 3, inversion: 0}
      )

    assert {:error, :missing_scale} = source.()
  end

  test "scale-generated source infers degree count from scale size when degrees are omitted" do
    source =
      ScaleGeneratedSource.source(
        scale: %{tonic: :c, family: :major_pentatonic, mode: 1},
        strategy: :tertian,
        shape: :triad,
        spelling_mode: :practical,
        render_defaults: %{octave: 3, inversion: 0}
      )

    assert {:ok, progression} = source.()
    chords = progression.chords
    assert length(chords) == 5
  end

  test "scale-generated source rejects degrees outside selected scale size" do
    source =
      ScaleGeneratedSource.source(
        degrees: [1, 6],
        scale: %{tonic: :c, family: :major_pentatonic, mode: 1},
        strategy: :tertian,
        shape: :triad,
        spelling_mode: :practical,
        render_defaults: %{octave: 3, inversion: 0}
      )

    assert {:error, {:invalid_degrees_for_scale, 5}} = source.()
  end

  test "ensure_bass_ascending enforces non-decreasing voiced bass" do
    first =
      ChordSpec.new!(%{
        harmonic_identity: %ChordSpec.HarmonicIdentity{root: :c, quality: :maj},
        octave: 3,
        inversion: 0,
        voicing: %ChordSpec.Voicing{center_note: 60}
      })

    second =
      ChordSpec.new!(%{
        harmonic_identity: %ChordSpec.HarmonicIdentity{root: :e, quality: :min},
        octave: 3,
        inversion: 0,
        voicing: %ChordSpec.Voicing{center_note: 60}
      })

    third =
      ChordSpec.new!(%{
        harmonic_identity: %ChordSpec.HarmonicIdentity{root: :d, quality: :min},
        octave: 3,
        inversion: 0,
        voicing: %ChordSpec.Voicing{center_note: 60}
      })

    middleware = EnsureBassAscending.middleware(include_foreign_bass: false)

    progression = %ChordProgression{
      name: "test",
      description: "test",
      chords: [first, second, third]
    }

    assert {:ok, %ChordProgression{chords: [a, b, c]}} = middleware.(progression)

    basses =
      [a, b, c]
      |> Enum.map(fn spec ->
        steps = Resolver.resolve_steps(spec)
        Enum.min(steps.voiced_chord_tones)
      end)

    assert basses == Enum.sort(basses)
  end

  test "progression.run composes middlewares" do
    source =
      ScaleGeneratedSource.source(
        degrees: [2, 5, 1],
        scale: %{tonic: :c, family: :major, mode: 1},
        strategy: :tertian,
        shape: :triad,
        spelling_mode: :practical,
        render_defaults: %{octave: 3, inversion: 0}
      )

    ensure = EnsureBassAscending.middleware(include_foreign_bass: false)

    assert {:ok, initial} = source.()
    assert {:ok, %ChordProgression{chords: chords}} = Progression.run(initial, [ensure])
    assert length(chords) == 3
  end

  test "progression.run_with_source runs source then transforms" do
    source =
      ScaleGeneratedSource.source(
        degrees: [2, 5, 1],
        scale: %{tonic: :c, family: :major, mode: 1},
        strategy: :tertian,
        shape: :triad,
        spelling_mode: :practical,
        render_defaults: %{octave: 3, inversion: 0}
      )

    ensure = EnsureBassAscending.middleware(include_foreign_bass: false)

    assert {:ok, %ChordProgression{chords: chords}} =
             Progression.run_with_source(source, [ensure])

    assert length(chords) == 3
  end

  test "create_with_fixed_chord source generates repeated chords" do
    source =
      CreateWithFixedChord.source(root: :d, quality: :min, count: 4, octave: 3, inversion: 0)

    assert {:ok, progression} = source.()
    chords = progression.chords
    assert length(chords) == 4
    assert Enum.all?(chords, &(ChordSpec.root(&1) == :d and ChordSpec.quality(&1) == :min))
  end

  test "transpose_all shifts resolved notes by octave when semitones is 12" do
    chord =
      ChordSpec.new!(%{
        harmonic_identity: %ChordSpec.HarmonicIdentity{root: :c, quality: :maj},
        octave: 3,
        inversion: 0
      })

    middleware = TransposeAll.middleware(semitones: 12)

    progression = %ChordProgression{name: "test", description: "test", chords: [chord]}
    assert {:ok, %ChordProgression{chords: [shifted]}} = middleware.(progression)

    original_notes = Resolver.resolve(chord)
    shifted_notes = Resolver.resolve(shifted)

    assert length(original_notes) == length(shifted_notes)

    assert Enum.zip(original_notes, shifted_notes)
           |> Enum.all?(fn {old_note, new_note} -> new_note - old_note == 12 end)
  end

  test "transpose_all supports non-octave semitone shifts" do
    chord =
      ChordSpec.new!(%{
        harmonic_identity: %ChordSpec.HarmonicIdentity{root: :g, quality: :min7},
        octave: 3,
        inversion: 1
      })

    middleware = TransposeAll.middleware(semitones: 5)

    progression = %ChordProgression{name: "test", description: "test", chords: [chord]}
    assert {:ok, %ChordProgression{chords: [shifted]}} = middleware.(progression)

    original_notes = Resolver.resolve(chord)
    shifted_notes = Resolver.resolve(shifted)

    assert length(original_notes) == length(shifted_notes)

    assert Enum.zip(original_notes, shifted_notes)
           |> Enum.all?(fn {old_note, new_note} -> new_note - old_note == 5 end)
  end

  test "run_with_source wraps source and transform failures" do
    bad_source = fn -> {:error, :bad_source} end
    bad_transform = fn _progression -> {:error, :bad_transform} end

    assert {:error, {:source_failed, :bad_source}} = Progression.run_with_source(bad_source, [])

    source =
      CreateWithFixedChord.source(root: :c, quality: :maj, count: 1, octave: 3, inversion: 0)

    assert {:error, {:transform_failed, 0, :bad_transform}} =
             Progression.run_with_source(source, [bad_transform])
  end
end
