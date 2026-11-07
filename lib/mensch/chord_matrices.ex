defmodule Mensch.ChordMatrices do
  @moduledoc """
  File-backed chord matrix storage.

  Matrices are persisted as Elixir terms under
  `lib/mensch/chord_matrices/data` by default.
  """

  alias Mensch.Harmony.ChordMatrix

  @type chord_matrix_record :: %{
          version: pos_integer(),
          id: String.t(),
          inserted_at: String.t(),
          updated_at: String.t(),
          chord_matrix: ChordMatrix.t()
        }

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
           ChordMatrix.new(%{number_rows: number_rows, number_columns: number_columns}) do
      storage_dir()
      |> ensure_storage_dir!()

      id = unique_id()
      now = now_iso8601()

      record = %{
        version: 1,
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
