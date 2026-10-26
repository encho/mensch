defmodule Mensch.Scale.ChordStrategy.Quintal do
  @moduledoc """
  Generates scale-derived quintal chords by stacking every fourth scale step.

  Example for a triad on degree 1: 1-5-2.
  Example for a seventh on degree 3: 3-7-4-1 (wrapped within the scale).
  """

  @behaviour Mensch.Scale.ChordStrategy

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Scale.ScaleGenerator
  alias Mensch.Scale.ScaleSpec

  @shape_steps %{
    triad: [0, 4, 8],
    seventh: [0, 4, 8, 12],
    ninth: [0, 4, 8, 12, 16],
    eleventh: [0, 4, 8, 12, 16, 20],
    thirteenth: [0, 4, 8, 12, 16, 20, 24]
  }

  @impl true
  def id, do: :quintal

  @impl true
  def label, do: "Quintal (stacked fifths)"

  @impl true
  def shapes, do: Map.keys(@shape_steps)

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
    steps = Map.fetch!(@shape_steps, shape)

    positions =
      Enum.map(steps, fn step ->
        rem(degree - 1 + step, size) + 1
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
