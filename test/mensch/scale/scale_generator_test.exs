defmodule Mensch.Scale.ScaleGeneratorTest do
  use ExUnit.Case, async: true

  alias Mensch.Scale.ModeResolver
  alias Mensch.Scale.ScaleGenerator
  alias Mensch.Scale.ScaleSpec

  test "scale notes examples" do
    c_ionian = build_spec!(:c, :major, 1)
    c_dorian = build_spec!(:c, :major, 2)
    c_natural_minor = build_spec!(:c, :major, 6)
    c_harmonic_minor = build_spec!(:c, :harmonic_minor, 1)
    c_melodic_minor = build_spec!(:c, :melodic_minor, 1)

    whole_tone =
      ScaleSpec.new!(%{
        tonic: :c,
        family: :whole_tone,
        mode: nil,
        name: "Whole-Tone",
        intervals: [0, 2, 4, 6, 8, 10]
      })

    c_major_pentatonic =
      ScaleSpec.new!(%{
        tonic: :c,
        family: :major_pentatonic,
        mode: nil,
        name: "Major Pentatonic",
        intervals: [0, 2, 4, 7, 9]
      })

    assert {:ok, ["C", "D", "E", "F", "G", "A", "B"]} = ScaleGenerator.notes(c_ionian)
    assert {:ok, ["C", "D", "Eb", "F", "G", "A", "Bb"]} = ScaleGenerator.notes(c_dorian)

    assert {:ok, ["C", "D", "Eb", "F", "G", "Ab", "Bb"]} =
             ScaleGenerator.notes(c_natural_minor)

    assert {:ok, ["C", "D", "Eb", "F", "G", "Ab", "B"]} = ScaleGenerator.notes(c_harmonic_minor)
    assert {:ok, ["C", "D", "Eb", "F", "G", "A", "B"]} = ScaleGenerator.notes(c_melodic_minor)
    assert {:ok, ["C", "D", "E", "F#", "G#", "Bb"]} = ScaleGenerator.notes(whole_tone)
    assert {:ok, ["C", "D", "E", "G", "A"]} = ScaleGenerator.notes(c_major_pentatonic)
  end

  test "strict enharmonic spelling examples" do
    db_major = build_spec!(:d_flat, :major, 1)
    fs_major = build_spec!(:f_sharp, :major, 1)
    eb_harmonic_minor_mode6 = build_spec!(:e_flat, :harmonic_minor, 6)

    assert {:ok, ["Db", "Eb", "F", "Gb", "Ab", "Bb", "C"]} =
             ScaleGenerator.notes(db_major, :strict)

    assert {:ok, ["F#", "G#", "A#", "B", "C#", "D#", "E#"]} =
             ScaleGenerator.notes(fs_major, :strict)

    assert {:ok, ["Eb", "F#", "G", "A", "Bb", "C", "D"]} =
             ScaleGenerator.notes(eb_harmonic_minor_mode6, :strict)
  end

  test "midi generation boundaries and membership" do
    spec = build_spec!(:c, :major, 2)

    assert {:ok, midi} = ScaleGenerator.midi_notes(spec, 0, 127)
    assert midi == Enum.sort(midi)
    assert Enum.uniq(midi) == midi
    assert Enum.all?(midi, &(&1 >= 0 and &1 <= 127))

    set = MapSet.new(spec.intervals)
    tonic_pc = 0

    assert Enum.all?(midi, fn note ->
             rem(note - tonic_pc + 120, 12) in set
           end)
  end

  test "midi boundary handling" do
    spec = build_spec!(:c, :major, 1)

    assert {:error, :invalid_range} = ScaleGenerator.midi_notes(spec, 128, 127)
    assert {:ok, midi} = ScaleGenerator.midi_notes(spec, 0, 127)
    assert List.first(midi) in [0, 2, 4, 5, 7, 9, 11]
    assert List.last(midi) <= 127
  end

  test "enharmonic tonics have same midi pitch set" do
    c_sharp_major = build_spec!(:c_sharp, :major, 1)
    d_flat_major = build_spec!(:d_flat, :major, 1)

    assert {:ok, midi_a} = ScaleGenerator.midi_notes(c_sharp_major, 0, 127)
    assert {:ok, midi_b} = ScaleGenerator.midi_notes(d_flat_major, 0, 127)
    assert midi_a == midi_b
  end

  test "full octave midi notes start and end on tonic" do
    spec = build_spec!(:c, :major, 1)

    assert {:ok, notes} = ScaleGenerator.midi_notes_full_octaves(spec, 21, 108)
    assert notes != []

    assert rem(List.first(notes), 12) == 0
    assert rem(List.last(notes), 12) == 0
    assert Enum.all?(notes, &(&1 >= List.first(notes) and &1 <= List.last(notes)))
  end

  test "full octave midi notes return empty when tonic span is incomplete" do
    spec = build_spec!(:c, :major, 1)

    assert {:ok, []} = ScaleGenerator.midi_notes_full_octaves(spec, 1, 11)
  end

  defp build_spec!(tonic, family, mode) do
    {:ok, resolved} = ModeResolver.resolve(family, mode)

    ScaleSpec.new!(%{
      tonic: tonic,
      family: family,
      mode: mode,
      name: resolved.name,
      intervals: resolved.intervals
    })
  end
end
