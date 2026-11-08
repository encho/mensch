defmodule Mensch.Harmony.ChordMatrix do
  @moduledoc """
  Matrix abstraction with explicit row and column counts.
  """

  alias Mensch.Harmony.ChordSpec

  defmodule Pad do
    @enforce_keys [:chord_spec]
    defstruct [:chord_spec]

    @type t :: %__MODULE__{chord_spec: ChordSpec.t()}
  end

  @default_time_signature {4, 4}
  @default_machine %{blueprint_id: "progression__alternating_wander__dv1", additional_params: %{}}

  @enforce_keys [:number_rows, :number_columns]
  defstruct [
    :number_rows,
    :number_columns,
    bpm: 120,
    time_signature: @default_time_signature,
    machine: @default_machine,
    assignments: %{}
  ]

  @type pad_key :: {non_neg_integer(), non_neg_integer()}

  @type pad_assignment :: Pad.t()

  @type t :: %__MODULE__{
          number_rows: pos_integer(),
          number_columns: pos_integer(),
          bpm: pos_integer(),
          time_signature: {pos_integer(), pos_integer()},
          machine: %{blueprint_id: String.t(), additional_params: map()},
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
         {:ok, bpm} <- parse_positive_integer(Map.get(attrs_map, :bpm, 120)),
         {:ok, time_signature} <-
           parse_time_signature(Map.get(attrs_map, :time_signature, @default_time_signature)),
         {:ok, machine} <- parse_machine_config(Map.get(attrs_map, :machine, @default_machine)),
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
         bpm: bpm,
         time_signature: time_signature,
         machine: machine,
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
        %{} = _source
      ) do
    with {:ok, normalized_row} <- parse_non_negative_integer(row),
         {:ok, normalized_column} <- parse_non_negative_integer(column),
         :ok <- ensure_in_bounds(chord_matrix, normalized_row, normalized_column) do
      {:ok,
       %__MODULE__{
         chord_matrix
         | assignments:
             Map.put(chord_matrix.assignments, {normalized_row, normalized_column}, %Pad{
               chord_spec: chord_spec
             })
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

  @spec set_bpm(t(), integer()) :: {:ok, t()} | {:error, term()}
  def set_bpm(%__MODULE__{} = chord_matrix, bpm) do
    with {:ok, normalized_bpm} <- parse_positive_integer(bpm) do
      {:ok, %__MODULE__{chord_matrix | bpm: normalized_bpm}}
    else
      {:error, :invalid_dimension} -> {:error, :invalid_bpm}
    end
  end

  def set_bpm(_chord_matrix, _bpm), do: {:error, :invalid_bpm}

  @spec set_time_signature(t(), {integer(), integer()}) :: {:ok, t()} | {:error, term()}
  def set_time_signature(%__MODULE__{} = chord_matrix, time_signature) do
    with {:ok, normalized_time_signature} <- parse_time_signature(time_signature) do
      {:ok, %__MODULE__{chord_matrix | time_signature: normalized_time_signature}}
    else
      {:error, :invalid_time_signature} -> {:error, :invalid_time_signature}
    end
  end

  def set_time_signature(_chord_matrix, _time_signature), do: {:error, :invalid_time_signature}

  @spec set_machine(t(), map()) :: {:ok, t()} | {:error, term()}
  def set_machine(%__MODULE__{} = chord_matrix, machine_config) do
    with {:ok, normalized_machine} <- parse_machine_config(machine_config) do
      {:ok, %__MODULE__{chord_matrix | machine: normalized_machine}}
    else
      {:error, :invalid_machine} -> {:error, :invalid_machine}
    end
  end

  def set_machine(_chord_matrix, _machine_config), do: {:error, :invalid_machine}

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
                 Map.put(acc, {row - 1, column}, assignment)

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
                 Map.put(acc, {row, column - 1}, assignment)

               {{row, column}, assignment}, acc ->
                 Map.put(acc, {row, column}, assignment)
             end)
       }}
    else
      false -> {:error, :minimum_columns}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec move_row_up(t(), integer()) :: {:ok, t()} | {:error, term()}
  def move_row_up(%__MODULE__{} = chord_matrix, row_index) do
    with {:ok, normalized_row_index} <- parse_non_negative_integer(row_index),
         :ok <- ensure_row_in_bounds(chord_matrix, normalized_row_index),
         true <- normalized_row_index > 0 do
      {:ok, swap_rows(chord_matrix, normalized_row_index, normalized_row_index - 1)}
    else
      false -> {:error, :out_of_bounds}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec move_row_down(t(), integer()) :: {:ok, t()} | {:error, term()}
  def move_row_down(%__MODULE__{} = chord_matrix, row_index) do
    with {:ok, normalized_row_index} <- parse_non_negative_integer(row_index),
         :ok <- ensure_row_in_bounds(chord_matrix, normalized_row_index),
         true <- normalized_row_index < chord_matrix.number_rows - 1 do
      {:ok, swap_rows(chord_matrix, normalized_row_index, normalized_row_index + 1)}
    else
      false -> {:error, :out_of_bounds}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec move_column_left(t(), integer()) :: {:ok, t()} | {:error, term()}
  def move_column_left(%__MODULE__{} = chord_matrix, column_index) do
    with {:ok, normalized_column_index} <- parse_non_negative_integer(column_index),
         :ok <- ensure_column_in_bounds(chord_matrix, normalized_column_index),
         true <- normalized_column_index > 0 do
      {:ok, swap_columns(chord_matrix, normalized_column_index, normalized_column_index - 1)}
    else
      false -> {:error, :out_of_bounds}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec move_column_right(t(), integer()) :: {:ok, t()} | {:error, term()}
  def move_column_right(%__MODULE__{} = chord_matrix, column_index) do
    with {:ok, normalized_column_index} <- parse_non_negative_integer(column_index),
         :ok <- ensure_column_in_bounds(chord_matrix, normalized_column_index),
         true <- normalized_column_index < chord_matrix.number_columns - 1 do
      {:ok, swap_columns(chord_matrix, normalized_column_index, normalized_column_index + 1)}
    else
      false -> {:error, :out_of_bounds}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(_value), do: {:error, :invalid_dimension}

  defp parse_non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_non_negative_integer(_value), do: {:error, :invalid_coordinate}

  defp parse_time_signature({num, den}) do
    with {:ok, parsed_num} <- parse_positive_integer(num),
         {:ok, parsed_den} <- parse_positive_integer(den) do
      {:ok, {parsed_num, parsed_den}}
    else
      {:error, :invalid_dimension} -> {:error, :invalid_time_signature}
    end
  end

  defp parse_time_signature(_value), do: {:error, :invalid_time_signature}

  defp parse_machine_config(%{} = machine_config) do
    blueprint_id =
      Map.get(machine_config, :blueprint_id) || Map.get(machine_config, "blueprint_id")

    additional_params =
      Map.get(machine_config, :additional_params) || Map.get(machine_config, "additional_params") ||
        %{}

    with {:ok, normalized_blueprint_id} <- parse_non_empty_string(blueprint_id),
         true <- is_map(additional_params) do
      {:ok,
       %{
         blueprint_id: normalized_blueprint_id,
         additional_params: normalize_map_string_keys(additional_params)
       }}
    else
      false -> {:error, :invalid_machine}
      {:error, :invalid_string} -> {:error, :invalid_machine}
    end
  end

  defp parse_machine_config(_value), do: {:error, :invalid_machine}

  defp parse_non_empty_string(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :invalid_string}
    else
      {:ok, trimmed}
    end
  end

  defp parse_non_empty_string(_value), do: {:error, :invalid_string}

  defp normalize_map_string_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: to_string(key)
      Map.put(acc, normalized_key, value)
    end)
  end

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
          Map.put(acc, {row + delta, column}, assignment)

        {{row, column}, assignment}, acc ->
          Map.put(acc, {row, column}, assignment)
      end)

    %__MODULE__{chord_matrix | assignments: shifted_assignments}
  end

  defp shift_columns(%__MODULE__{} = chord_matrix, start_index, delta) do
    shifted_assignments =
      Enum.reduce(chord_matrix.assignments, %{}, fn
        {{row, column}, assignment}, acc when column >= start_index ->
          Map.put(acc, {row, column + delta}, assignment)

        {{row, column}, assignment}, acc ->
          Map.put(acc, {row, column}, assignment)
      end)

    %__MODULE__{chord_matrix | assignments: shifted_assignments}
  end

  defp swap_rows(%__MODULE__{} = chord_matrix, row_a, row_b) do
    swapped_assignments =
      Enum.reduce(chord_matrix.assignments, %{}, fn
        {{row, column}, assignment}, acc when row == row_a ->
          Map.put(acc, {row_b, column}, assignment)

        {{row, column}, assignment}, acc when row == row_b ->
          Map.put(acc, {row_a, column}, assignment)

        {{row, column}, assignment}, acc ->
          Map.put(acc, {row, column}, assignment)
      end)

    %__MODULE__{chord_matrix | assignments: swapped_assignments}
  end

  defp swap_columns(%__MODULE__{} = chord_matrix, column_a, column_b) do
    swapped_assignments =
      Enum.reduce(chord_matrix.assignments, %{}, fn
        {{row, column}, assignment}, acc when column == column_a ->
          Map.put(acc, {row, column_b}, assignment)

        {{row, column}, assignment}, acc when column == column_b ->
          Map.put(acc, {row, column_a}, assignment)

        {{row, column}, assignment}, acc ->
          Map.put(acc, {row, column}, assignment)
      end)

    %__MODULE__{chord_matrix | assignments: swapped_assignments}
  end

  defp parse_assignments(assignments, number_rows, number_columns) when is_map(assignments) do
    Enum.reduce_while(assignments, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, {row, column}} <- parse_pad_key(key),
           true <- row < number_rows and column < number_columns,
           {:ok, assignment} <- parse_assignment(value) do
        {:cont, {:ok, Map.put(acc, {row, column}, assignment)}}
      else
        false -> {:halt, {:error, :out_of_bounds}}
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

  defp parse_assignment(%Pad{chord_spec: %ChordSpec{} = chord_spec}) do
    {:ok, %Pad{chord_spec: chord_spec}}
  end

  defp parse_assignment(%{} = value) do
    case Map.get(value, :chord_spec) do
      %ChordSpec{} = chord_spec -> {:ok, %Pad{chord_spec: chord_spec}}
      _ -> {:error, :invalid_assignment}
    end
  end

  defp parse_assignment(_value), do: {:error, :invalid_assignment}
end
