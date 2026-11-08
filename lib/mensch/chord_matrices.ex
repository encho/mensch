defmodule Mensch.ChordMatrices do
  @moduledoc """
  File-backed chord matrix storage.

  Matrices are persisted as Elixir terms under
  `lib/mensch/chord_matrices/data` by default.
  """

  alias Mensch.Harmony.ChordMatrix
  alias Mensch.Harmony.ChordSpec
  alias Mensch.SampleBlueprint

  @type chord_matrix_record :: %{
          version: pos_integer(),
          id: String.t(),
          inserted_at: String.t(),
          updated_at: String.t(),
          chord_matrix: ChordMatrix.t()
        }

  @current_version 6

  @spec list_chord_matrices() :: [map()]
  def list_chord_matrices do
    storage_dir()
    |> ensure_storage_dir!()

    storage_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".exs"))
    |> Enum.map(fn filename ->
      id = Path.rootname(filename)

      case fetch_chord_matrix(id) do
        {:ok, record} ->
          %{
            id: record.id,
            number_rows: record.chord_matrix.number_rows,
            number_columns: record.chord_matrix.number_columns,
            updated_at: record.updated_at
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at, :desc)
  end

  @spec fetch_chord_matrix(String.t()) :: {:ok, chord_matrix_record()} | {:error, term()}
  def fetch_chord_matrix(id) when is_binary(id) do
    path = chord_matrix_path(id)

    if File.exists?(path) do
      case read_term_file(path) do
        {:ok, %{} = record} ->
          normalize_loaded_record(id, record)

        {:ok, _other} ->
          {:error, :invalid_chord_matrix_format}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end

  @spec create_chord_matrix(integer(), integer()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def create_chord_matrix(number_rows, number_columns)
      when is_integer(number_rows) and is_integer(number_columns) do
    with {:ok, chord_matrix} <-
           ChordMatrix.new(%{
             number_rows: number_rows,
             number_columns: number_columns,
             machine: default_machine_config()
           }) do
      storage_dir()
      |> ensure_storage_dir!()

      id = unique_id()
      now = now_iso8601()

      record = %{
        version: @current_version,
        id: id,
        inserted_at: now,
        updated_at: now,
        chord_matrix: chord_matrix
      }

      with :ok <- write_term_file(chord_matrix_path(id), record) do
        {:ok, record}
      end
    else
      {:error, :invalid_dimension} -> {:error, :invalid_dimension}
    end
  end

  def create_chord_matrix(_number_rows, _number_columns), do: {:error, :invalid_params}

  @spec assign_chord_to_pad(String.t(), integer(), integer(), ChordSpec.t(), map()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def assign_chord_to_pad(
        id,
        row,
        column,
        %ChordSpec{} = chord_spec,
        %{} = source
      )
      when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.assign_chord_to_pad(chord_matrix, row, column, chord_spec, source)
    end)
  end

  def assign_chord_to_pad(_id, _row, _column, _chord_spec, _source),
    do: {:error, :invalid_params}

  @spec clear_pad_assignment(String.t(), integer(), integer()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def clear_pad_assignment(id, row, column) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.clear_pad_assignment(chord_matrix, row, column)
    end)
  end

  def clear_pad_assignment(_id, _row, _column), do: {:error, :invalid_params}

  @spec insert_row_before(String.t(), integer()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def insert_row_before(id, row_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.insert_row_before(chord_matrix, row_index)
    end)
  end

  def insert_row_before(_id, _row_index), do: {:error, :invalid_params}

  @spec insert_row_after(String.t(), integer()) :: {:ok, chord_matrix_record()} | {:error, term()}
  def insert_row_after(id, row_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.insert_row_after(chord_matrix, row_index)
    end)
  end

  def insert_row_after(_id, _row_index), do: {:error, :invalid_params}

  @spec remove_row(String.t(), integer()) :: {:ok, chord_matrix_record()} | {:error, term()}
  def remove_row(id, row_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.remove_row(chord_matrix, row_index)
    end)
  end

  def remove_row(_id, _row_index), do: {:error, :invalid_params}

  @spec insert_column_left(String.t(), integer()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def insert_column_left(id, column_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.insert_column_left(chord_matrix, column_index)
    end)
  end

  def insert_column_left(_id, _column_index), do: {:error, :invalid_params}

  @spec insert_column_right(String.t(), integer()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def insert_column_right(id, column_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.insert_column_right(chord_matrix, column_index)
    end)
  end

  def insert_column_right(_id, _column_index), do: {:error, :invalid_params}

  @spec remove_column(String.t(), integer()) :: {:ok, chord_matrix_record()} | {:error, term()}
  def remove_column(id, column_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.remove_column(chord_matrix, column_index)
    end)
  end

  def remove_column(_id, _column_index), do: {:error, :invalid_params}

  @spec move_row_up(String.t(), integer()) :: {:ok, chord_matrix_record()} | {:error, term()}
  def move_row_up(id, row_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.move_row_up(chord_matrix, row_index)
    end)
  end

  def move_row_up(_id, _row_index), do: {:error, :invalid_params}

  @spec move_row_down(String.t(), integer()) :: {:ok, chord_matrix_record()} | {:error, term()}
  def move_row_down(id, row_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.move_row_down(chord_matrix, row_index)
    end)
  end

  def move_row_down(_id, _row_index), do: {:error, :invalid_params}

  @spec move_column_left(String.t(), integer()) :: {:ok, chord_matrix_record()} | {:error, term()}
  def move_column_left(id, column_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.move_column_left(chord_matrix, column_index)
    end)
  end

  def move_column_left(_id, _column_index), do: {:error, :invalid_params}

  @spec move_column_right(String.t(), integer()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def move_column_right(id, column_index) when is_binary(id) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.move_column_right(chord_matrix, column_index)
    end)
  end

  def move_column_right(_id, _column_index), do: {:error, :invalid_params}

  @spec update_bpm(String.t(), integer()) :: {:ok, chord_matrix_record()} | {:error, term()}
  def update_bpm(id, bpm) when is_binary(id) and is_integer(bpm) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.set_bpm(chord_matrix, bpm)
    end)
  end

  def update_bpm(_id, _bpm), do: {:error, :invalid_params}

  @spec update_duration_mbeats(String.t(), integer()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def update_duration_mbeats(id, duration_mbeats)
      when is_binary(id) and is_integer(duration_mbeats) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.set_duration_mbeats(chord_matrix, duration_mbeats)
    end)
  end

  def update_duration_mbeats(_id, _duration_mbeats), do: {:error, :invalid_params}

  @spec update_time_signature(String.t(), {integer(), integer()}) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def update_time_signature(id, {num, den} = time_signature)
      when is_binary(id) and is_integer(num) and is_integer(den) do
    update_chord_matrix(id, fn chord_matrix ->
      ChordMatrix.set_time_signature(chord_matrix, time_signature)
    end)
  end

  def update_time_signature(_id, _time_signature), do: {:error, :invalid_params}

  @spec update_machine(String.t(), String.t(), map()) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def update_machine(id, blueprint_id, additional_params)
      when is_binary(id) and is_binary(blueprint_id) and is_map(additional_params) do
    with {:ok, machine_config} <- normalize_machine_config(blueprint_id, additional_params) do
      update_chord_matrix(id, fn chord_matrix ->
        ChordMatrix.set_machine(chord_matrix, machine_config)
      end)
    end
  end

  def update_machine(_id, _blueprint_id, _additional_params), do: {:error, :invalid_params}

  @spec assign_progression_to_row(String.t(), integer(), String.t(), String.t(), [ChordSpec.t()]) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def assign_progression_to_row(id, row_index, progression_id, progression_name, chords)
      when is_binary(id) and is_integer(row_index) and is_binary(progression_id) and
             is_binary(progression_name) and is_list(chords) do
    update_chord_matrix(id, fn chord_matrix ->
      assign_progression_to_axis(
        chord_matrix,
        :row,
        row_index,
        progression_id,
        progression_name,
        chords
      )
    end)
  end

  def assign_progression_to_row(_id, _row_index, _progression_id, _progression_name, _chords),
    do: {:error, :invalid_params}

  @spec assign_progression_to_column(String.t(), integer(), String.t(), String.t(), [
          ChordSpec.t()
        ]) ::
          {:ok, chord_matrix_record()} | {:error, term()}
  def assign_progression_to_column(id, column_index, progression_id, progression_name, chords)
      when is_binary(id) and is_integer(column_index) and is_binary(progression_id) and
             is_binary(progression_name) and is_list(chords) do
    update_chord_matrix(id, fn chord_matrix ->
      assign_progression_to_axis(
        chord_matrix,
        :column,
        column_index,
        progression_id,
        progression_name,
        chords
      )
    end)
  end

  def assign_progression_to_column(
        _id,
        _column_index,
        _progression_id,
        _progression_name,
        _chords
      ),
      do: {:error, :invalid_params}

  defp normalize_loaded_record(id, %{} = record) do
    with chord_matrix_value when not is_nil(chord_matrix_value) <- Map.get(record, :chord_matrix),
         {:ok, chord_matrix} <- normalize_chord_matrix(chord_matrix_value) do
      {:ok,
       %{
         version: Map.get(record, :version, 1),
         id: Map.get(record, :id, id),
         inserted_at: Map.get(record, :inserted_at, now_iso8601()),
         updated_at: Map.get(record, :updated_at, now_iso8601()),
         chord_matrix: chord_matrix
       }}
    else
      nil -> {:error, :missing_chord_matrix}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_chord_matrix(%ChordMatrix{} = chord_matrix), do: ChordMatrix.new(chord_matrix)
  defp normalize_chord_matrix(%{} = chord_matrix_map), do: ChordMatrix.new(chord_matrix_map)
  defp normalize_chord_matrix(_), do: {:error, :invalid_chord_matrix}

  defp update_chord_matrix(id, updater) when is_function(updater, 1) do
    with {:ok, record} <- fetch_chord_matrix(id),
         {:ok, updated_chord_matrix} <- updater.(record.chord_matrix) do
      updated_record = %{
        record
        | version: @current_version,
          updated_at: now_iso8601(),
          chord_matrix: updated_chord_matrix
      }

      with :ok <- write_term_file(chord_matrix_path(id), updated_record) do
        {:ok, updated_record}
      end
    end
  end

  defp assign_progression_to_axis(
         %ChordMatrix{} = chord_matrix,
         axis,
         axis_index,
         progression_id,
         progression_name,
         chords
       )
       when axis in [:row, :column] do
    with true <- Enum.all?(chords, &match?(%ChordSpec{}, &1)),
         :ok <- ensure_axis_index_in_bounds(chord_matrix, axis, axis_index) do
      capacity = axis_capacity(chord_matrix, axis)
      chords_for_slots = Enum.take(chords, capacity)
      chord_count = length(chords_for_slots)

      0..(capacity - 1)
      |> Enum.reduce_while({:ok, chord_matrix}, fn offset, {:ok, acc} ->
        {row, column} = axis_coordinate(axis, axis_index, offset)

        if offset < chord_count do
          chord_spec = Enum.at(chords_for_slots, offset)

          case ChordMatrix.assign_chord_to_pad(acc, row, column, chord_spec, %{
                 source_progression_id: progression_id,
                 source_progression_name: progression_name,
                 source_chord_index: offset
               }) do
            {:ok, next} -> {:cont, {:ok, next}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        else
          case ChordMatrix.clear_pad_assignment(acc, row, column) do
            {:ok, next} -> {:cont, {:ok, next}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end
      end)
    else
      false -> {:error, :invalid_params}
      {:error, reason} -> {:error, reason}
    end
  end

  defp axis_capacity(%ChordMatrix{} = chord_matrix, :row), do: chord_matrix.number_columns
  defp axis_capacity(%ChordMatrix{} = chord_matrix, :column), do: chord_matrix.number_rows

  defp axis_coordinate(:row, row_index, offset), do: {row_index, offset}
  defp axis_coordinate(:column, column_index, offset), do: {offset, column_index}

  defp ensure_axis_index_in_bounds(%ChordMatrix{} = chord_matrix, :row, axis_index) do
    if axis_index >= 0 and axis_index < chord_matrix.number_rows,
      do: :ok,
      else: {:error, :out_of_bounds}
  end

  defp ensure_axis_index_in_bounds(%ChordMatrix{} = chord_matrix, :column, axis_index) do
    if axis_index >= 0 and axis_index < chord_matrix.number_columns,
      do: :ok,
      else: {:error, :out_of_bounds}
  end

  defp default_machine_config do
    blueprint_id = SampleBlueprint.default_blueprint_id()

    case SampleBlueprint.default_additional_params(blueprint_id) do
      {:ok, additional_params} ->
        %{
          blueprint_id: blueprint_id,
          additional_params: normalize_map_string_keys(additional_params)
        }

      {:error, _reason} ->
        %{blueprint_id: blueprint_id, additional_params: %{}}
    end
  end

  defp normalize_machine_config(blueprint_id, additional_params) do
    with {:ok, schema} <- SampleBlueprint.additional_param_schema(blueprint_id),
         {:ok, defaults} <- SampleBlueprint.default_additional_params(blueprint_id),
         {:ok, normalized_additional} <-
           normalize_machine_additional(additional_params, schema, defaults) do
      {:ok, %{blueprint_id: blueprint_id, additional_params: normalized_additional}}
    end
  end

  defp normalize_machine_additional(additional_params, schema, defaults)
       when is_map(additional_params) and is_list(schema) and is_map(defaults) do
    incoming = normalize_map_string_keys(additional_params)
    normalized_defaults = normalize_map_string_keys(defaults)
    allowed_keys = MapSet.new(Enum.map(schema, & &1.name))

    unknown_keys =
      incoming
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.difference(allowed_keys)
      |> MapSet.to_list()

    if unknown_keys != [] do
      {:error, "unknown machine parameters: #{Enum.join(unknown_keys, ", ")}"}
    else
      schema
      |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, acc} ->
        raw_value =
          Map.get(incoming, field.name, Map.get(normalized_defaults, field.name, field.default))

        case normalize_machine_field_value(field, raw_value) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, field.name, value)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp normalize_machine_additional(_additional_params, _schema, _defaults),
    do: {:error, "machine additional params must be a map"}

  defp normalize_machine_field_value(%{type: :int, name: name} = field, raw_value) do
    with {:ok, value} <- parse_int(raw_value, name),
         :ok <- validate_min_max(value, field, name) do
      {:ok, value}
    end
  end

  defp normalize_machine_field_value(%{type: :float, name: name} = field, raw_value) do
    with {:ok, value} <- parse_float(raw_value, name),
         :ok <- validate_min_max(value, field, name) do
      {:ok, value}
    end
  end

  defp normalize_machine_field_value(%{type: :enum, name: name, options: options}, raw_value)
       when is_list(options) do
    allowed_values = Enum.map(options, & &1.value)
    value = to_string(raw_value)

    if value in allowed_values do
      {:ok, value}
    else
      {:error, "#{name} must be one of: #{Enum.join(allowed_values, ", ")}"}
    end
  end

  defp normalize_machine_field_value(%{type: :enum, name: name}, _raw_value),
    do: {:error, "#{name} enum schema is invalid"}

  defp normalize_machine_field_value(%{name: name}, _raw_value),
    do: {:error, "unsupported machine field type for #{name}"}

  defp validate_min_max(value, field, name) do
    min = Map.get(field, :min)
    max = Map.get(field, :max)

    cond do
      not is_nil(min) and value < min ->
        {:error, "#{name} must be >= #{min}"}

      not is_nil(max) and value > max ->
        {:error, "#{name} must be <= #{max}"}

      true ->
        :ok
    end
  end

  defp parse_int(value, _field) when is_integer(value), do: {:ok, value}

  defp parse_int(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, "#{field} must be an integer"}
    end
  end

  defp parse_int(_value, field), do: {:error, "#{field} must be an integer"}

  defp parse_float(value, _field) when is_float(value), do: {:ok, value}
  defp parse_float(value, _field) when is_integer(value), do: {:ok, value * 1.0}

  defp parse_float(value, field) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, "#{field} must be a float"}
    end
  end

  defp parse_float(_value, field), do: {:error, "#{field} must be a float"}

  defp normalize_map_string_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: to_string(key)
      Map.put(acc, normalized_key, value)
    end)
  end

  defp unique_id do
    timestamp =
      DateTime.utc_now() |> DateTime.truncate(:second) |> Calendar.strftime("%Y_%m_%d_%H_%M_%S")

    suffix = System.unique_integer([:positive, :monotonic])
    "chord_matrix_#{timestamp}_#{suffix}"
  end

  defp write_term_file(path, term) do
    tmp_path = path <> ".tmp"

    content =
      inspect(term,
        pretty: true,
        limit: :infinity,
        printable_limit: :infinity,
        width: 100,
        charlists: :as_lists
      )

    with :ok <- File.write(tmp_path, IO.iodata_to_binary(content) <> "\n"),
         :ok <- File.rename(tmp_path, path) do
      :ok
    end
  end

  defp read_term_file(path) do
    try do
      {term, _binding} = Code.eval_file(path)
      {:ok, term}
    rescue
      error -> {:error, {:parse_error, Exception.message(error)}}
    end
  end

  defp ensure_storage_dir!(dir) do
    File.mkdir_p!(dir)
    dir
  end

  defp chord_matrix_path(id), do: Path.join(storage_dir(), id <> ".exs")

  defp storage_dir do
    Application.get_env(
      :mensch,
      :chord_matrices_dir,
      Path.expand("lib/mensch/chord_matrices/data", File.cwd!())
    )
  end

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
