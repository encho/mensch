defmodule Mensch.ChordProgressions do
  @moduledoc """
  File-backed chord progression storage.

  Progressions are persisted as Elixir terms under
  `lib/mensch/chord_progressions/data` by default.
  """

  alias Mensch.Harmony.ChordProgression

  @type progression_record :: %{
          version: pos_integer(),
          id: String.t(),
          inserted_at: String.t(),
          updated_at: String.t(),
          progression: ChordProgression.t()
        }

  @spec list_progressions() :: [map()]
  def list_progressions do
    storage_dir()
    |> ensure_storage_dir!()

    storage_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".exs"))
    |> Enum.map(fn filename ->
      id = Path.rootname(filename)

      case fetch_progression(id) do
        {:ok, record} ->
          %{
            id: record.id,
            name: record.progression.name,
            description: record.progression.description,
            chord_count: length(record.progression.chords),
            updated_at: record.updated_at
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at, :desc)
  end

  @spec fetch_progression(String.t()) :: {:ok, progression_record()} | {:error, term()}
  def fetch_progression(id) when is_binary(id) do
    path = progression_path(id)

    if File.exists?(path) do
      case read_term_file(path) do
        {:ok, %{} = record} ->
          normalize_loaded_record(id, record)

        {:ok, _other} ->
          {:error, :invalid_progression_format}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end

  @spec create_progression(String.t(), String.t(), [Mensch.Harmony.ChordSpec.t()]) ::
          {:ok, progression_record()} | {:error, term()}
  def create_progression(name, description, chords)
      when is_binary(name) and is_binary(description) and is_list(chords) do
    cleaned_name = String.trim(name)

    cond do
      cleaned_name == "" ->
        {:error, :name_required}

      true ->
        with {:ok, progression} <-
               ChordProgression.new(%{
                 name: cleaned_name,
                 description: description,
                 chords: chords
               }) do
          storage_dir()
          |> ensure_storage_dir!()

          id = unique_id_for_name(cleaned_name)
          now = now_iso8601()

          record = %{
            version: 1,
            id: id,
            inserted_at: now,
            updated_at: now,
            progression: progression
          }

          with :ok <- write_term_file(progression_path(id), record) do
            {:ok, record}
          end
        end
    end
  end

  def create_progression(_name, _description, _chords), do: {:error, :invalid_params}

  @spec merge_progressions(String.t(), String.t(), [String.t()]) ::
          {:ok, progression_record()} | {:error, term()}
  def merge_progressions(name, description, source_ids)
      when is_binary(name) and is_binary(description) and is_list(source_ids) do
    cleaned_ids =
      source_ids
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    cond do
      cleaned_ids == [] ->
        {:error, :no_sources_selected}

      true ->
        with {:ok, source_records} <- fetch_progression_records(cleaned_ids),
             merged_chords <- Enum.flat_map(source_records, & &1.progression.chords),
             false <- merged_chords == [],
             {:ok, record} <- create_progression(name, description, merged_chords) do
          {:ok, record}
        else
          true -> {:error, :no_chords_to_merge}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def merge_progressions(_name, _description, _source_ids), do: {:error, :invalid_params}

  defp normalize_loaded_record(id, %{} = record) do
    with progression_value when not is_nil(progression_value) <- Map.get(record, :progression),
         {:ok, progression} <- normalize_progression(progression_value) do
      {:ok,
       %{
         version: Map.get(record, :version, 1),
         id: Map.get(record, :id, id),
         inserted_at: Map.get(record, :inserted_at, now_iso8601()),
         updated_at: Map.get(record, :updated_at, now_iso8601()),
         progression: progression
       }}
    else
      nil -> {:error, :missing_progression}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_progression(%ChordProgression{} = progression),
    do: ChordProgression.new(progression)

  defp normalize_progression(%{} = progression_map), do: ChordProgression.new(progression_map)
  defp normalize_progression(_), do: {:error, :invalid_progression}

  defp unique_id_for_name(name) do
    base = slugify(name)

    Enum.reduce_while(0..9999, nil, fn idx, _acc ->
      candidate = if idx == 0, do: base, else: "#{base}_#{idx + 1}"

      if File.exists?(progression_path(candidate)) do
        {:cont, nil}
      else
        {:halt, candidate}
      end
    end)
  end

  defp slugify(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")

    if slug == "", do: "chord_progression", else: slug
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

  defp progression_path(id), do: Path.join(storage_dir(), id <> ".exs")

  defp storage_dir do
    Application.get_env(
      :mensch,
      :chord_progressions_dir,
      Path.expand("lib/mensch/chord_progressions/data", File.cwd!())
    )
  end

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp fetch_progression_records(ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case fetch_progression(id) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, {:source_load_failed, id, reason}}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      {:error, reason} -> {:error, reason}
    end
  end
end
