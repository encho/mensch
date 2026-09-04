defmodule Mensch.Scale do
  @moduledoc """
  Pure harmonic math: chromatic note classes, scale interval tables, and
  resolution of scale degrees to note names.

  This module owns no state; it is a set of functions used by
  `Mensch.Machine.SingleNote` to resolve a pitch against a
  `Mensch.HarmonicContext`.
  """

  @note_classes [:c, :cs, :d, :ds, :e, :f, :fs, :g, :gs, :a, :as, :b]

  @note_labels %{
    c: "C",
    cs: "C#",
    d: "D",
    ds: "D#",
    e: "E",
    f: "F",
    fs: "F#",
    g: "G",
    gs: "G#",
    a: "A",
    as: "A#",
    b: "B"
  }

  @scales %{major: [0, 2, 4, 5, 7, 9, 11]}

  @type note_class :: :c | :cs | :d | :ds | :e | :f | :fs | :g | :gs | :a | :as | :b
  @type scale_name :: :major

  @doc """
  Resolves a 1-based scale `degree` against `root`/`scale` to a note class
  plus an octave shift (degrees beyond the scale's span wrap into the
  next/previous octave).
  """
  @spec degree_to_note(note_class(), scale_name(), integer()) :: {note_class(), integer()}
  def degree_to_note(root, scale, degree) do
    intervals = Map.fetch!(@scales, scale)
    degree_count = length(intervals)
    zero_based = degree - 1
    octave_shift = Integer.floor_div(zero_based, degree_count)
    degree_index = Integer.mod(zero_based, degree_count)
    semitone_offset = Enum.at(intervals, degree_index)

    root_index = Enum.find_index(@note_classes, &(&1 == root))
    note_index = Integer.mod(root_index + semitone_offset, 12)

    {Enum.at(@note_classes, note_index), octave_shift}
  end

  @doc "Formats a note class and octave as a note name, e.g. `:cs, 4 -> \"C#4\"`."
  @spec note_name(note_class(), integer()) :: String.t()
  def note_name(note_class, octave), do: "#{label(note_class)}#{octave}"

  @doc "All chromatic note classes in order, for cycling/selection."
  @spec note_classes() :: [note_class()]
  def note_classes, do: @note_classes

  @doc "Human-readable label for a note class, e.g. `:cs -> \"C#\"`."
  @spec label(note_class()) :: String.t()
  def label(note_class), do: Map.fetch!(@note_labels, note_class)
end
