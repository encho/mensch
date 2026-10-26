defmodule Mensch.Scale.ChordGeneratorTest do
  use ExUnit.Case, async: true

  alias Mensch.Scale
  alias Mensch.Scale.ChordGenerator

  test "lists available strategy options" do
    options = ChordGenerator.strategy_options()

    assert Enum.any?(options, &(&1.id == :tertian))
    assert Enum.any?(options, &(&1.id == :quartal))
    assert Enum.any?(options, &(&1.id == :quintal))

    tertian = Enum.find(options, &(&1.id == :tertian))
    assert tertian.label == "Tertian (stacked thirds)"
    assert :triad in tertian.shapes
    assert :thirteenth in tertian.shapes
    assert :add6 in tertian.shapes
    assert :six_nine in tertian.shapes

    quartal = Enum.find(options, &(&1.id == :quartal))
    assert quartal.label == "Quartal (stacked fourths)"
    assert :triad in quartal.shapes

    quintal = Enum.find(options, &(&1.id == :quintal))
    assert quintal.label == "Quintal (stacked fifths)"
    assert :triad in quintal.shapes
  end

  test "generates c ionian triad on degree 1" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    assert {:ok, chord} =
             Scale.generate_chord(scale_spec, 1, strategy: :tertian, shape: :triad)

    assert chord.note_names == ["C", "E", "G"]
    assert chord.pitch_classes == [0, 4, 7]
    assert chord.root_note == "C"
    assert chord.root_pitch_class == 0
  end

  test "generates c dorian seventh on degree 2" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 2)

    assert {:ok, chord} =
             Scale.generate_chord(scale_spec, 2, strategy: :tertian, shape: :seventh)

    assert chord.note_names == ["D", "F", "A", "C"]
    assert chord.pitch_classes == [2, 5, 9, 0]
    assert chord.root_note == "D"
  end

  test "supports standalone scale families" do
    {:ok, scale_spec} = Scale.build_scale(:c, :whole_tone, nil)

    assert {:ok, chord} =
             Scale.generate_chord(scale_spec, 1, strategy: :tertian, shape: :triad)

    assert chord.note_names == ["C", "E", "G#"]
    assert chord.pitch_classes == [0, 4, 8]
  end

  test "supports add6 shape under tertian strategy" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    assert {:ok, chord} =
             Scale.generate_chord(scale_spec, 1,
               strategy: :tertian,
               shape: :add6
             )

    assert chord.note_names == ["C", "E", "G", "A"]
    assert chord.pitch_classes == [0, 4, 7, 9]
  end

  test "supports six_nine shape under tertian strategy" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    assert {:ok, chord} =
             Scale.generate_chord(scale_spec, 1,
               strategy: :tertian,
               shape: :six_nine
             )

    assert chord.note_names == ["C", "E", "G", "A", "D"]
    assert chord.pitch_classes == [0, 4, 7, 9, 2]
  end

  test "generates quartal strict chord" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    assert {:ok, chord} =
             Scale.generate_chord(scale_spec, 1,
               strategy: :quartal,
               shape: :triad
             )

    assert chord.note_names == ["C", "F", "B"]
    assert chord.pitch_classes == [0, 5, 11]
  end

  test "generates quintal strict chord" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    assert {:ok, chord} =
             Scale.generate_chord(scale_spec, 1,
               strategy: :quintal,
               shape: :triad
             )

    assert chord.note_names == ["C", "G", "D"]
    assert chord.pitch_classes == [0, 7, 2]
  end

  test "rejects out-of-range degree" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    assert {:error, {:degree_out_of_range, 8, 7}} =
             Scale.generate_chord(scale_spec, 8, strategy: :tertian, shape: :triad)
  end

  test "rejects unknown strategy" do
    {:ok, scale_spec} = Scale.build_scale(:c, :major, 1)

    assert {:error, {:unknown_strategy, :secundal}} =
             Scale.generate_chord(scale_spec, 1, strategy: :secundal, shape: :triad)
  end
end
