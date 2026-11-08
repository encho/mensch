defmodule Mensch.Harmony.ChordMatrix do
  @moduledoc """
  Matrix abstraction with explicit row and column counts.
  """

  alias Mensch.Harmony.ChordSpec

  @enforce_keys [:number_rows, :number_columns]
  defstruct [:number_rows, :number_columns, assignments: %{}]

  @type pad_key :: {non_neg_integer(), non_neg_integer()}

  @type pad_assignment :: %{
          row: non_neg_integer(),
          column: non_neg_integer(),
          chord_spec: ChordSpec.t(),
          source_progression_id: String.t(),
          source_progression_name: String.t(),
          source_chord_index: non_neg_integer()
        }

  @type t :: %__MODULE__{
          number_rows: pos_integer(),
          number_columns: pos_integer(),
          assignments: %{optional(pad_key()) => pad_assignment()}
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(%{} = attrs) do
    attrs_map =
      case attrs do
        %__MODULE__{} = chord_matrix -> Map.from_struct(chord_matrix)
        _ -> attrs
      end

    with {:ok, number_rows} <- parse_positive_integer(Map.get(attrs_map, :number_rows)),
         {:ok, number_columns} <- parse_positive_integer(Map.get(attrs_map, :number_columns)),
         {:ok, assignments} <-
           parse_assignments(
             Map.get(attrs_map, :assignments, %{}),
             number_rows,
             number_columns
           ) do
      {:ok,
       %__MODULE__{
         number_rows: number_rows,
         number_columns: number_columns,
         assignments: assignments
       }}
    end
  end

  def new(_attrs), do: {:error, :invalid_chord_matrix}

  @spec assign_chord_to_pad(
          t(),
          integer(),
          integer(),
          ChordSpec.t(),
          map()
        ) :: {:ok, t()} | {:error, term()}
  def assign_chord_to_pad(
        %__MODULE__{} = chord_matrix,
        row,
        column,
        %ChordSpec{} = chord_spec,
        %{} = source
      ) do
    with {:ok, normalized_row} <- parse_non_negative_integer(row),
         {:ok, normalized_column} <- parse_non_negative_integer(column),
         :ok <- ensure_in_bounds(chord_matrix, normalized_row, normalized_column),
         {:ok, assignment} <-
           parse_assignment(
             %{
               row: normalized_row,
               column: normalized_column,
               chord_spec: chord_spec,
               source_progression_id: Map.get(source, :source_progression_id),
               source_progression_name: Map.get(source, :source_progression_name),
               source_chord_index: Map.get(source, :source_chord_index)
             },
             chord_matrix.number_rows,
             chord_matrix.number_columns
           ) do
      {:ok,
       %__MODULE__{
         chord_matrix
         | assignments:
             Map.put(chord_matrix.assignments, {normalized_row, normalized_column}, assignment)
       }}
    end
  end

  def assign_chord_to_pad(_chord_matrix, _row, _column, _chord_spec, _source),
    do: {:error, :invalid_assignment}

  @spec clear_pad_assignment(t(), integer(), integer()) :: {:ok, t()} | {:error, term()}
  def clear_pad_assignment(%__MODULE__{} = chord_matrix, row, column) do
    with {:ok, normalized_row} <- parse_non_negative_integer(row),
         {:ok, normalized_column} <- parse_non_negative_integer(column),
         :ok <- ensure_in_bounds(chord_matrix, normalized_row, normalized_column) do
      {:ok,
       %__MODULE__{
         chord_matrix
         | assignments: Map.delete(chord_matrix.assignments, {normalized_row, normalized_column})
       }}
    end
  end

  @spec assignment_at(t(), integer(), integer()) :: pad_assignment() | nil
  def assignment_at(%__MODULE__{} = chord_matrix, row, column)
      when is_integer(row) and is_integer(column) do
    Map.get(chord_matrix.assignments, {row, column})
  end

  def assignment_at(_chord_matrix, _row, _column), do: nil

  @spec insert_row_before(t(), integer()) :: {:ok, t()} | {:error, term()}
  def insert_row_before(%__MODULE__{} = chord_matrix, row_index) do
    with {:ok, normalized_row_index} <- parse_non_negative_integer(row_index),
         :ok <- ensure_row_in_bounds(chord_matrix, normalized_row_index) do
      {:ok,
       shift_rows(chord_matrix, normalized_row_index, +1)
       |> Map.update!(:number_rows, &(&1 + 1))}
    end
  end

  @spec insert_row_after(t(), integer()) :: {:ok, t()} | {:error, term()}
  def insert_row_after(%__MODULE__{} = chord_matrix, row_index) do
    with {:ok, normalized_row_index} <- parse_non_negative_integer(row_index),
         :ok <- ensure_row_in_bounds(chord_matrix, normalized_row_index) do
      insertion_index = normalized_row_index + 1

      {:ok,
       shift_rows(chord_matrix, insertion_index, +1)
       |> Map.update!(:number_rows, &(&1 + 1))}
    end
  end

  @spec remove_row(t(), integer()) :: {:ok, t()} | {:error, term()}
  def remove_row(%__MODULE__{} = chord_matrix, row_index) do
    with true <- chord_matrix.number_rows > 1,
         {:ok, normalized_row_index} <- parse_non_negative_integer(row_index),
         :ok <- ensure_row_in_bounds(chord_matrix, normalized_row_index) do
      {:ok,
       %__MODULE__{
         chord_matrix
         | number_rows: chord_matrix.number_rows - 1,
           assignments:
             chord_matrix.assignments
             |> Enum.reduce(%{}, fn
               {{^normalized_row_index, _column}, _assignment}, acc ->
                 acc

               {{row, column}, assignment}, acc when row > normalized_row_index ->
                 updated_assignment = %{assignment | row: row - 1}
                 Map.put(acc, {row - 1, column}, updated_assignment)

               {{row, column}, assignment}, acc ->
                 Map.put(acc, {row, column}, assignment)
             end)
       }}
    else
      false -> {:error, :minimum_rows}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec insert_column_left(t(), integer()) :: {:ok, t()} | {:error, term()}
  def insert_column_left(%__MODULE__{} = chord_matrix, column_index) do
    with {:ok, normalized_column_index} <- parse_non_negative_integer(column_index),
         :ok <- ensure_column_in_bounds(chord_matrix, normalized_column_index) do
      {:ok,
       shift_columns(chord_matrix, normalized_column_index, +1)
       |> Map.update!(:number_columns, &(&1 + 1))}
    end
  end

  @spec insert_column_right(t(), integer()) :: {:ok, t()} | {:error, term()}
  def insert_column_right(%__MODULE__{} = chord_matrix, column_index) do
    with {:ok, normalized_column_index} <- parse_non_negative_integer(column_index),
         :ok <- ensure_column_in_bounds(chord_matrix, normalized_column_index) do
      insertion_index = normalized_column_index + 1

      {:ok,
       shift_columns(chord_matrix, insertion_index, +1)
       |> Map.update!(:number_columns, &(&1 + 1))}
    end
  end

  @spec remove_column(t(), integer()) :: {:ok, t()} | {:error, term()}
  def remove_column(%__MODULE__{} = chord_matrix, column_index) do
    with true <- chord_matrix.number_columns > 1,
         {:ok, normalized_column_index} <- parse_non_negative_integer(column_index),
         :ok <- ensure_column_in_bounds(chord_matrix, normalized_column_index) do
      {:ok,
       %__MODULE__{
         chord_matrix
         | number_columns: chord_matrix.number_columns - 1,
           assignments:
             chord_matrix.assignments
             |> Enum.reduce(%{}, fn
               {{_row, ^normalized_column_index}, _assignment}, acc ->
                 acc

               {{row, column}, assignment}, acc when column > normalized_column_index ->
                 updated_assignment = %{assignment | column: column - 1}
                 Map.put(acc, {row, column - 1}, updated_assignment)

               {{row, column}, assignment}, acc ->
                 Map.put(acc, {row, column}, assignment)
             end)
       }}
    else
      false -> {:error, :minimum_columns}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(_value), do: {:error, :invalid_dimension}

  defp parse_non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_non_negative_integer(_value), do: {:error, :invalid_coordinate}

  defp ensure_in_bounds(%__MODULE__{} = chord_matrix, row, column) do
    if row < chord_matrix.number_rows and column < chord_matrix.number_columns do
      :ok
    else
      {:error, :out_of_bounds}
    end
  end

  defp ensure_row_in_bounds(%__MODULE__{} = chord_matrix, row) do
    if row < chord_matrix.number_rows do
      :ok
    else
      {:error, :out_of_bounds}
    end
  end

  defp ensure_column_in_bounds(%__MODULE__{} = chord_matrix, column) do
    if column < chord_matrix.number_columns do
      :ok
    else
      {:error, :out_of_bounds}
    end
  end

  defp shift_rows(%__MODULE__{} = chord_matrix, start_index, delta) do
    shifted_assignments =
      Enum.reduce(chord_matrix.assignments, %{}, fn
        {{row, column}, assignment}, acc when row >= start_index ->
          updated_assignment = %{assignment | row: row + delta}
          Map.put(acc, {row + delta, column}, updated_assignment)

        {{row, column}, assignment}, acc ->
          Map.put(acc, {row, column}, assignment)
      end)

    %__MODULE__{chord_matrix | assignments: shifted_assignments}
  end

  defp shift_columns(%__MODULE__{} = chord_matrix, start_index, delta) do
    shifted_assignments =
      Enum.reduce(chord_matrix.assignments, %{}, fn
        {{row, column}, assignment}, acc when column >= start_index ->
          updated_assignment = %{assignment | column: column + delta}
          Map.put(acc, {row, column + delta}, updated_assignment)

        {{row, column}, assignment}, acc ->
          Map.put(acc, {row, column}, assignment)
      end)

    %__MODULE__{chord_matrix | assignments: shifted_assignments}
  end

  defp parse_assignments(assignments, number_rows, number_columns) when is_map(assignments) do
    Enum.reduce_while(assignments, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, {row, column}} <- parse_pad_key(key),
           {:ok, assignment} <- parse_assignment(value, number_rows, number_columns) do
        {:cont, {:ok, Map.put(acc, {row, column}, assignment)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_assignments(_assignments, _number_rows, _number_columns),
    do: {:error, :invalid_assignments}

  defp parse_pad_key({row, column}) do
    with {:ok, normalized_row} <- parse_non_negative_integer(row),
         {:ok, normalized_column} <- parse_non_negative_integer(column) do
      {:ok, {normalized_row, normalized_column}}
    end
  end

  defp parse_pad_key(_key), do: {:error, :invalid_assignment_key}

  defp parse_assignment(value, number_rows, number_columns) when is_map(value) do
    with {:ok, row} <- parse_non_negative_integer(Map.get(value, :row)),
         {:ok, column} <- parse_non_negative_integer(Map.get(value, :column)),
         true <- row < number_rows and column < number_columns,
         %ChordSpec{} = chord_spec <- Map.get(value, :chord_spec),
         {:ok, source_progression_id} <-
           parse_non_empty_string(Map.get(value, :source_progression_id)),
         {:ok, source_progression_name} <-
           parse_non_empty_string(Map.get(value, :source_progression_name)),
         {:ok, source_chord_index} <-
           parse_non_negative_integer(Map.get(value, :source_chord_index)) do
      {:ok,
       %{
         row: row,
         column: column,
         chord_spec: chord_spec,
         source_progression_id: source_progression_id,
         source_progression_name: source_progression_name,
         source_chord_index: source_chord_index
       }}
    else
      false -> {:error, :out_of_bounds}
      nil -> {:error, :invalid_assignment}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_assignment}
    end
  end

  defp parse_assignment(_value, _number_rows, _number_columns), do: {:error, :invalid_assignment}

  defp parse_non_empty_string(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :invalid_assignment}
    else
      {:ok, trimmed}
    end
  end

  defp parse_non_empty_string(_value), do: {:error, :invalid_assignment}
end
