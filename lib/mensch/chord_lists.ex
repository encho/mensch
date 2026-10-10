defmodule Mensch.ChordLists do
  @moduledoc """
  File-backed chord list storage for Chord Lab.

  Lists are persisted as Elixir terms under `lib/mensch/chord_lists/data` by default.
  """

  alias Mensch.Harmony.ChordSpec.Parameters

  @type list_entry :: %{
          id: String.t(),
          inserted_at: String.t(),
          parameters: Parameters.t(),
          snapshot: map()
        }

  @type chord_list :: %{
          version: pos_integer(),
          id: String.t(),
          name: String.t(),
          inserted_at: String.t(),
          updated_at: String.t(),
          entries: [list_entry()]
        }

  @spec list_lists() :: [map()]
  def list_lists do
    storage_dir()
    |> ensure_storage_dir!()

    storage_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".exs"))
    |> Enum.map(fn filename ->
      id = Path.rootname(filename)

      case fetch_list(id) do
        {:ok, list} ->
          %{
            id: list.id,
            name: list.name,
            entry_count: length(list.entries),
            updated_at: list.updated_at
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  @spec fetch_list(String.t()) :: {:ok, chord_list()} | {:error, term()}
  def fetch_list(id) when is_binary(id) do
    path = list_path(id)

    if File.exists?(path) do
      case read_term_file(path) do
        {:ok, %{} = list} ->
          normalized = normalize_loaded_list(id, list)
          maybe_rewrite_legacy_file(path, normalized)
          {:ok, normalized}

        {:ok, _other} ->
          {:error, :invalid_list_format}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end

  @spec create_list(String.t()) :: {:ok, chord_list()} | {:error, term()}
  def create_list(name) when is_binary(name) do
    cleaned_name = String.trim(name)

    if cleaned_name == "" do
      {:error, :name_required}
    else
      storage_dir()
      |> ensure_storage_dir!()

      id = unique_id_for_name(cleaned_name)
      now = now_iso8601()

      list = %{
        version: 1,
        id: id,
        name: cleaned_name,
        inserted_at: now,
        updated_at: now,
        entries: []
      }

      with :ok <- write_term_file(list_path(id), list) do
        {:ok, list}
      end
    end
  end

  @spec add_entry(String.t(), map(), map() | nil) :: {:ok, chord_list()} | {:error, term()}
  def add_entry(list_id, values, result) when is_binary(list_id) and is_map(values) do
    with {:ok, list} <- fetch_list(list_id) do
      with {:ok, parameters} <- Parameters.from_values_map(values) do
        entry = %{
          id: Integer.to_string(System.unique_integer([:positive, :monotonic])),
          inserted_at: now_iso8601(),
          parameters: parameters,
          snapshot: build_snapshot(result)
        }

        updated = %{
          list
          | entries: list.entries ++ [entry],
            updated_at: now_iso8601()
        }

        with :ok <- write_term_file(list_path(list.id), updated) do
          {:ok, updated}
        end
      end
    end
  end

  @spec delete_entry(String.t(), String.t()) :: {:ok, chord_list()} | {:error, term()}
  def delete_entry(list_id, entry_id) when is_binary(list_id) and is_binary(entry_id) do
    with {:ok, list} <- fetch_list(list_id) do
      updated = %{
        list
        | entries: Enum.reject(list.entries, &(&1.id == entry_id)),
          updated_at: now_iso8601()
      }

      with :ok <- write_term_file(list_path(list.id), updated) do
        {:ok, updated}
      end
    end
  end

  @spec move_entry(String.t(), String.t(), :up | :down) :: {:ok, chord_list()} | {:error, term()}
  def move_entry(list_id, entry_id, direction)
      when is_binary(list_id) and is_binary(entry_id) and direction in [:up, :down] do
    with {:ok, list} <- fetch_list(list_id),
         {:ok, reordered_entries} <- reorder_entries(list.entries, entry_id, direction) do
      updated = %{
        list
        | entries: reordered_entries,
          updated_at: now_iso8601()
      }

      with :ok <- write_term_file(list_path(list.id), updated) do
        {:ok, updated}
      end
    end
  end

  defp build_snapshot(nil), do: %{}

  defp build_snapshot(result) when is_map(result) do
    %{
      resolved_chord_tones: normalize_note_list(Map.get(result, :resolved_chord_tones, [])),
      inverted_chord_tones: normalize_note_list(Map.get(result, :inverted_chord_tones, [])),
      voiced_chord_tones: normalize_note_list(Map.get(result, :voiced_chord_tones, [])),
      foreign_bass_note: Map.get(result, :foreign_bass_note),
      final_notes: normalize_note_list(Map.get(result, :final_notes, [])),
      final_note_details: Map.get(result, :final_note_details, [])
    }
  end

  defp normalize_loaded_list(id, %{} = list) do
    %{
      version: Map.get(list, :version, 1),
      id: Map.get(list, :id, id),
      name: Map.get(list, :name, id),
      inserted_at: Map.get(list, :inserted_at, now_iso8601()),
      updated_at: Map.get(list, :updated_at, now_iso8601()),
      entries: normalize_entries(Map.get(list, :entries, []))
    }
  end

  defp normalize_entries(entries) when is_list(entries) do
    Enum.map(entries, fn entry ->
      snapshot = Map.get(entry, :snapshot, %{})

      normalized_snapshot = %{
        resolved_chord_tones: normalize_note_list(Map.get(snapshot, :resolved_chord_tones, [])),
        inverted_chord_tones: normalize_note_list(Map.get(snapshot, :inverted_chord_tones, [])),
        voiced_chord_tones: normalize_note_list(Map.get(snapshot, :voiced_chord_tones, [])),
        foreign_bass_note: Map.get(snapshot, :foreign_bass_note),
        final_notes: normalize_note_list(Map.get(snapshot, :final_notes, [])),
        final_note_details: Map.get(snapshot, :final_note_details, [])
      }

      parameters = normalize_parameters(entry)

      entry
      |> Map.put(:parameters, parameters)
      |> Map.delete(:values)
      |> Map.put(:snapshot, normalized_snapshot)
    end)
  end

  defp normalize_entries(_entries), do: []

  defp normalize_parameters(entry) do
    cond do
      match?(%Parameters{}, Map.get(entry, :parameters)) ->
        Map.get(entry, :parameters)

      is_map(Map.get(entry, :values)) ->
        case Parameters.from_values_map(Map.get(entry, :values)) do
          {:ok, parameters} -> parameters
          {:error, _reason} -> %Parameters{}
        end

      true ->
        %Parameters{}
    end
  end

  defp normalize_note_list(notes) when is_list(notes) do
    notes
    |> Enum.filter(&is_integer/1)
  end

  defp normalize_note_list(_notes), do: []

  defp maybe_rewrite_legacy_file(path, normalized) do
    case File.read(path) do
      {:ok, content} ->
        if String.contains?(content, "~c\"") or String.contains?(content, ":values =>") or
             String.contains?(content, "_unused_voicing_type") do
          _ = write_term_file(path, normalized)
          :ok
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp reorder_entries(entries, entry_id, direction) do
    current_index = Enum.find_index(entries, &(&1.id == entry_id))

    case current_index do
      nil ->
        {:error, :entry_not_found}

      _ ->
        target_index =
          case direction do
            :up -> max(current_index - 1, 0)
            :down -> min(current_index + 1, length(entries) - 1)
          end

        if target_index == current_index do
          {:ok, entries}
        else
          current_entry = Enum.at(entries, current_index)
          target_entry = Enum.at(entries, target_index)

          swapped =
            entries
            |> List.replace_at(current_index, target_entry)
            |> List.replace_at(target_index, current_entry)

          {:ok, swapped}
        end
    end
  end

  defp unique_id_for_name(name) do
    base = slugify(name)

    Enum.reduce_while(0..9999, nil, fn idx, _acc ->
      candidate = if idx == 0, do: base, else: "#{base}_#{idx + 1}"

      if File.exists?(list_path(candidate)) do
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

    if slug == "", do: "chord_list", else: slug
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

  defp list_path(id), do: Path.join(storage_dir(), id <> ".exs")

  defp storage_dir do
    Application.get_env(
      :mensch,
      :chord_lists_dir,
      Path.expand("lib/mensch/chord_lists/data", File.cwd!())
    )
  end

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
