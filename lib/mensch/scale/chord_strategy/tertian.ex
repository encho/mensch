defmodule Mensch.Scale.ChordStrategy.Tertian do
  @moduledoc """
  Generates scale-derived tertian chords by stacking every other scale degree.

  Example for a triad on degree 2: 2-4-6.
  Example for a seventh on degree 5: 5-7-2-4 (wrapped within the scale).
  """

  @behaviour Mensch.Scale.ChordStrategy

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Scale.ScaleGenerator
  alias Mensch.Scale.ScaleSpec

  @shape_degree_offsets %{
    triad: [1, 3, 5],
    seventh: [1, 3, 5, 7],
    ninth: [1, 3, 5, 7, 9],
    eleventh: [1, 3, 5, 7, 9, 11],
    thirteenth: [1, 3, 5, 7, 9, 11, 13],
    add6: [1, 3, 5, 6],
    six_nine: [1, 3, 5, 6, 9]
  }

  @impl true
  def id, do: :tertian

  @impl true
  def label, do: "Tertian (stacked thirds)"

  @impl true
  def shapes, do: Map.keys(@shape_degree_offsets)

  @impl true
  def generate(%ScaleSpec{} = scale_spec, degree, opts) when is_integer(degree) and degree > 0 do
    with :ok <- validate_degree(scale_spec, degree),
         {:ok, shape} <- parse_shape(opts),
         {:ok, note_names} <- ScaleGenerator.notes(scale_spec),
         {:ok, tonic_pc} <- tonic_pitch_class(scale_spec),
         {:ok, positions} <- degree_positions(scale_spec, degree, shape),
         {:ok, chord_notes} <- notes_from_positions(note_names, positions),
         {:ok, chord_intervals} <- intervals_from_positions(scale_spec, positions),
         {:ok, pitch_classes} <- pitch_classes_from_intervals(tonic_pc, chord_intervals),
         {:ok, root_note} <- fetch_root(chord_notes),
         {:ok, root_pitch_class} <- fetch_root(pitch_classes) do
      {:ok,
       %{
         strategy: id(),
         shape: shape,
         degree: degree,
         root_note: root_note,
         root_pitch_class: root_pitch_class,
         note_names: chord_notes,
         pitch_classes: pitch_classes,
         scale_degree_positions: positions,
         scale_intervals_from_tonic: chord_intervals
       }}
    end
  end

  def generate(%ScaleSpec{}, _degree, _opts), do: {:error, :invalid_degree}
  def generate(_scale_spec, _degree, _opts), do: {:error, :invalid_scale_spec}

  defp parse_shape(opts) do
    shape = Keyword.get(opts, :shape, :triad)

    if shape in shapes() do
      {:ok, shape}
    else
      {:error, {:invalid_shape, shape}}
    end
  end

  defp validate_degree(%ScaleSpec{intervals: intervals}, degree) do
    size = length(intervals)

    cond do
      size == 0 -> {:error, :empty_scale}
      degree < 1 -> {:error, :invalid_degree}
      degree > size -> {:error, {:degree_out_of_range, degree, size}}
      true -> :ok
    end
  end

  defp degree_positions(%ScaleSpec{intervals: intervals}, degree, shape) do
    size = length(intervals)
    degree_offsets = Map.fetch!(@shape_degree_offsets, shape)

    positions =
      Enum.map(degree_offsets, fn degree_offset ->
        rem(degree - 1 + degree_offset - 1, size) + 1
      end)

    {:ok, positions}
  end

  defp notes_from_positions(scale_notes, positions) do
    chord_notes = Enum.map(positions, fn pos -> Enum.at(scale_notes, pos - 1) end)

    if Enum.any?(chord_notes, &is_nil/1) do
      {:error, :invalid_position_lookup}
    else
      {:ok, chord_notes}
    end
  end

  defp intervals_from_positions(%ScaleSpec{intervals: intervals}, positions) do
    chord_intervals = Enum.map(positions, fn pos -> Enum.at(intervals, pos - 1) end)

    if Enum.any?(chord_intervals, &is_nil/1) do
      {:error, :invalid_position_lookup}
    else
      {:ok, chord_intervals}
    end
  end

  defp pitch_classes_from_intervals(tonic_pc, intervals) do
    {:ok, Enum.map(intervals, &rem(tonic_pc + &1, 12))}
  end

  defp fetch_root([value | _rest]), do: {:ok, value}
  defp fetch_root([]), do: {:error, :empty_chord}

  defp tonic_pitch_class(%ScaleSpec{tonic: tonic}) do
    case ChordSpec.pitch_class_to_semitone(tonic) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, :invalid_tonic}
    end
  end
end
