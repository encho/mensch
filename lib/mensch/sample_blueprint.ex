defmodule Mensch.SampleBlueprint do
  @moduledoc """
  Orchestrates sample generation from chord collections via pluggable blueprints.

  Global sample settings are validated here. Blueprint-specific additional
  params are validated from each blueprint schema, then delegated to that
  blueprint to build full sample entries.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.Parameters
  alias Mensch.SampleDefinition
  alias Mensch.SampleBlueprints.Registry
  alias Mensch.SampleEntry
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @default_folder "Generated"
  @default_frame_mbeats 50
  @default_time_signature {4, 4}

  @spec available_blueprints() :: [%{id: String.t(), label: String.t()}]
  def available_blueprints, do: Registry.available_blueprints()

  @spec default_blueprint_id() :: String.t()
  def default_blueprint_id, do: Registry.default_blueprint_id()

  @spec additional_param_schema(String.t() | atom()) :: {:ok, [map()]} | {:error, String.t()}
  def additional_param_schema(blueprint_id) do
    with {:ok, module} <- Registry.fetch(blueprint_id) do
      {:ok, module.additional_param_schema()}
    end
  end

  @spec default_additional_params(String.t() | atom()) :: {:ok, map()} | {:error, String.t()}
  def default_additional_params(blueprint_id) do
    with {:ok, module} <- Registry.fetch(blueprint_id) do
      {:ok, module.default_additional_params()}
    end
  end

  @spec build(map()) :: {:ok, SampleDefinition.t()} | {:error, String.t()}
  def build(opts) when is_map(opts) do
    with {:ok, normalized} <- normalize_build_opts(opts) do
      build_from_normalized(normalized)
    end
  end

  @spec build!(map()) :: SampleDefinition.t()
  def build!(opts) do
    case build(opts) do
      {:ok, sample} -> sample
      {:error, reason} -> raise ArgumentError, "invalid sample blueprint: #{reason}"
    end
  end

  @spec export_to_sample_db(map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def export_to_sample_db(opts, export_opts \\ []) when is_map(opts) and is_list(export_opts) do
    register? = Keyword.get(export_opts, :register, true)
    module_suffix = Keyword.get(export_opts, :module_suffix)

    with {:ok, normalized} <- normalize_build_opts(opts),
         {:ok, sample} <- build_from_normalized(normalized),
         {:ok, module_name, file_name} <- module_and_file_name(sample, module_suffix),
         :ok <- write_export_module(module_name, file_name, sample),
         :ok <- maybe_register_module(module_name, register?) do
      {:ok, %{sample: sample, module: module_name, file: file_name, registered: register?}}
    end
  end

  @doc """
  Rewrites all generated sample provider modules as static materialized data.

  This removes runtime blueprint building from generated sample files while
  preserving the `sample(frame_mbeats)` provider contract.
  """
  @spec migrate_generated_sample_modules(keyword()) :: {:ok, [String.t()]} | {:error, String.t()}
  def migrate_generated_sample_modules(opts \\ []) when is_list(opts) do
    frame_mbeats = Keyword.get(opts, :frame_mbeats, @default_frame_mbeats)
    generated_files = Path.wildcard("lib/mensch/sample_db/generated_*.ex")

    generated_files
    |> Enum.reduce_while({:ok, []}, fn file, {:ok, acc} ->
      module = module_for_generated_file(file)

      with {:ok, _module} <- ensure_loaded(module),
           true <- function_exported?(module, :sample, 1),
           %SampleDefinition{} = sample <- module.sample(frame_mbeats),
           :ok <- write_export_module(module, file, sample) do
        {:cont, {:ok, [file | acc]}}
      else
        false ->
          {:halt, {:error, "generated module does not export sample/1: #{inspect(module)}"}}

        {:error, reason} ->
          {:halt, {:error, reason}}

        other ->
          {:halt,
           {:error,
            "failed to materialize generated module #{inspect(module)}: #{inspect(other)}"}}
      end
    end)
    |> case do
      {:ok, files} -> {:ok, Enum.reverse(files)}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [ArgumentError, RuntimeError] -> {:error, Exception.message(error)}
  end

  defp normalize_build_opts(opts) do
    with {:ok, name} <- parse_required_string(opts[:name] || opts["name"], "name"),
         {:ok, folder} <- parse_optional_string(opts[:folder] || opts["folder"], @default_folder),
         {:ok, id} <- parse_optional_string(opts[:id] || opts["id"], generated_id(name)),
         {:ok, created_at} <- parse_created_at(opts[:created_at] || opts["created_at"]),
         {:ok, blueprint_id} <-
           parse_required_string(opts[:blueprint_id] || opts["blueprint_id"], "blueprint_id"),
         {:ok, blueprint_module} <- Registry.fetch(blueprint_id),
         {:ok, bpm} <- parse_positive_integer(opts[:bpm] || opts["bpm"], "bpm"),
         {:ok, time_signature} <-
           parse_time_signature(
             opts[:time_signature] || opts["time_signature"] || @default_time_signature
           ),
         {:ok, frame_mbeats} <-
           parse_positive_integer(
             opts[:frame_mbeats] || opts["frame_mbeats"] || @default_frame_mbeats,
             "frame_mbeats"
           ),
         {:ok, chord_duration_mbeats} <-
           parse_positive_integer(
             opts[:chord_duration_mbeats] || opts["chord_duration_mbeats"],
             "chord_duration_mbeats"
           ),
         {:ok, silence_after_chord_mbeats} <-
           parse_non_negative_integer(
             opts[:silence_after_chord_mbeats] || opts["silence_after_chord_mbeats"] || 0,
             "silence_after_chord_mbeats"
           ),
         {:ok, chords} <- normalize_chords(opts[:chords] || opts["chords"] || []),
         {:ok, additional_params} <-
           normalize_additional_params(
             opts[:blueprint_additional_params] || opts["blueprint_additional_params"] || %{},
             blueprint_module.additional_param_schema()
           ) do
      {:ok,
       %{
         id: id,
         created_at: created_at,
         folder: folder,
         name: name,
         blueprint_id: blueprint_id,
         blueprint_module: blueprint_module,
         bpm: bpm,
         time_signature: time_signature,
         frame_mbeats: frame_mbeats,
         chord_duration_mbeats: chord_duration_mbeats,
         silence_after_chord_mbeats: silence_after_chord_mbeats,
         chords: chords,
         blueprint_additional_params: additional_params
       }}
    end
  end

  defp build_from_normalized(normalized) do
    sample_context =
      SampleContext.new!(%{
        bpm: normalized.bpm,
        time_signature: normalized.time_signature,
        frame_mbeats: normalized.frame_mbeats
      })

    with {:ok, entries} <-
           normalized.blueprint_module.build_sample_entries(%{
             chords: normalized.chords,
             sample_context: sample_context,
             chord_duration_mbeats: normalized.chord_duration_mbeats,
             silence_after_chord_mbeats: normalized.silence_after_chord_mbeats,
             additional_params: normalized.blueprint_additional_params
           }),
         :ok <- validate_entries(entries),
         total_length_mbeats <- total_length_mbeats(entries, sample_context) do
      {:ok,
       SampleDefinition.new!(%{
         id: normalized.id,
         created_at: normalized.created_at,
         folder: normalized.folder,
         name: normalized.name,
         sample_context: sample_context,
         sample_entries: entries,
         total_length_mbeats: total_length_mbeats,
         blueprint_meta: %{
           blueprint_id: normalized.blueprint_id,
           bpm: normalized.bpm,
           time_signature: normalized.time_signature,
           frame_mbeats: normalized.frame_mbeats,
           chord_duration_mbeats: normalized.chord_duration_mbeats,
           silence_after_chord_mbeats: normalized.silence_after_chord_mbeats,
           blueprint_additional_params: normalized.blueprint_additional_params
         }
       })}
    end
  rescue
    error in [ArgumentError, RuntimeError] -> {:error, Exception.message(error)}
  end

  defp validate_entries(entries) when is_list(entries) do
    cond do
      entries == [] ->
        {:error, "generated sample has no entries"}

      Enum.any?(entries, &(not match?(%SampleEntry{}, &1))) ->
        {:error, "generated sample entries must be typed sample entries"}

      true ->
        :ok
    end
  end

  defp validate_entries(_), do: {:error, "generated sample entries must be a list"}

  defp total_length_mbeats(entries, %SampleContext{} = sample_context) do
    entries
    |> Enum.map(fn entry ->
      entry
      |> Map.fetch!(:timeline_context)
      |> TimelineContext.end_mbeat(sample_context)
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp normalize_additional_params(additional_params, schema)
       when is_map(additional_params) and is_list(schema) do
    normalized_schema_keys = MapSet.new(Enum.map(schema, & &1.name))

    incoming_keys =
      additional_params
      |> normalize_map_string_keys()
      |> Map.keys()
      |> MapSet.new()

    unknown_keys = MapSet.difference(incoming_keys, normalized_schema_keys) |> MapSet.to_list()

    if unknown_keys != [] do
      {:error, "unknown additional params: #{Enum.join(unknown_keys, ", ")}"}
    else
      incoming = normalize_map_string_keys(additional_params)

      schema
      |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, acc} ->
        case normalize_field_value(field, Map.get(incoming, field.name)) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, field.name, value)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp normalize_additional_params(_additional_params, _schema),
    do: {:error, "blueprint_additional_params must be a map"}

  defp normalize_field_value(field, nil), do: normalize_field_value(field, field.default)
  defp normalize_field_value(field, ""), do: normalize_field_value(field, field.default)

  defp normalize_field_value(%{type: :int, name: name} = field, raw_value) do
    with {:ok, value} <- parse_int(raw_value, name),
         :ok <- validate_min_max(value, field, name) do
      {:ok, value}
    end
  end

  defp normalize_field_value(%{type: :float, name: name} = field, raw_value) do
    with {:ok, value} <- parse_float(raw_value, name),
         :ok <- validate_min_max(value, field, name) do
      {:ok, value}
    end
  end

  defp normalize_field_value(%{type: :enum, name: name, options: options}, raw_value)
       when is_list(options) do
    allowed_values = Enum.map(options, & &1.value)
    value = to_string(raw_value)

    if value in allowed_values do
      {:ok, value}
    else
      {:error, "#{name} must be one of: #{Enum.join(allowed_values, ", ")}"}
    end
  end

  defp normalize_field_value(%{type: :enum, name: name}, _raw_value),
    do: {:error, "#{name} enum schema is invalid"}

  defp normalize_field_value(%{name: name}, _raw_value),
    do: {:error, "unsupported field type for #{name}"}

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

  defp parse_required_string(value, field) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:error, "#{field} is required"}, else: {:ok, trimmed}
  end

  defp parse_required_string(_, field), do: {:error, "#{field} is required"}

  defp parse_optional_string(value, default) when is_binary(value) do
    trimmed = String.trim(value)
    {:ok, if(trimmed == "", do: default, else: trimmed)}
  end

  defp parse_optional_string(nil, default), do: {:ok, default}
  defp parse_optional_string(_, default), do: {:ok, default}

  defp parse_created_at(nil), do: {:ok, DateTime.utc_now() |> DateTime.truncate(:second)}

  defp parse_created_at(%DateTime{} = created_at),
    do: {:ok, DateTime.truncate(created_at, :second)}

  defp parse_created_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, created_at, _offset} -> {:ok, DateTime.truncate(created_at, :second)}
      _ -> {:error, "created_at must be an ISO8601 timestamp"}
    end
  end

  defp parse_created_at(_), do: {:error, "created_at must be a DateTime or ISO8601 timestamp"}

  defp parse_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp parse_positive_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, "#{field} must be a positive integer"}
    end
  end

  defp parse_positive_integer(_value, field), do: {:error, "#{field} must be a positive integer"}

  defp parse_non_negative_integer(value, _field) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp parse_non_negative_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, "#{field} must be a non-negative integer"}
    end
  end

  defp parse_non_negative_integer(_value, field),
    do: {:error, "#{field} must be a non-negative integer"}

  defp parse_time_signature({num, den})
       when is_integer(num) and num > 0 and is_integer(den) and den > 0,
       do: {:ok, {num, den}}

  defp parse_time_signature(%{"numerator" => num, "denominator" => den}) do
    with {:ok, parsed_num} <- parse_positive_integer(num, "time_signature.numerator"),
         {:ok, parsed_den} <- parse_positive_integer(den, "time_signature.denominator") do
      {:ok, {parsed_num, parsed_den}}
    end
  end

  defp parse_time_signature(_), do: {:error, "invalid time_signature"}

  defp normalize_chords(chords) when is_list(chords) do
    normalized =
      Enum.map(chords, fn chord ->
        case normalize_chord(chord) do
          {:ok, value} -> value
          {:error, _reason} -> nil
        end
      end)

    if normalized == [] or Enum.any?(normalized, &is_nil/1) do
      {:error, "all chords must be valid harmony chord specs or chord parameters"}
    else
      {:ok, normalized}
    end
  end

  defp normalize_chords(_), do: {:error, "chords must be a list"}

  defp normalize_chord(%ChordSpec{} = chord_spec) do
    chord_spec
    |> Map.from_struct()
    |> ChordSpec.new()
  end

  defp normalize_chord(%Parameters{} = parameters) do
    parameters
    |> Parameters.to_chord_spec_attrs()
    |> ChordSpec.new()
  end

  defp normalize_chord(attrs) when is_map(attrs), do: ChordSpec.new(attrs)
  defp normalize_chord(_), do: {:error, :invalid_chord}

  defp generated_id(name) do
    base = slugify(name)
    suffix = :erlang.unique_integer([:positive, :monotonic])
    "#{base}-#{suffix}"
  end

  defp module_and_file_name(sample, nil) do
    id = Map.fetch!(sample, :id)
    suffix = id |> slugify() |> Macro.camelize()
    module_name = "Mensch.SampleDb.Generated#{suffix}"
    file_name = "lib/mensch/sample_db/generated_#{slugify(id)}.ex"
    {:ok, module_name, file_name}
  end

  defp module_and_file_name(sample, module_suffix) when is_binary(module_suffix) do
    trimmed = String.trim(module_suffix)

    if trimmed == "" do
      module_and_file_name(sample, nil)
    else
      module_piece = Macro.camelize(slugify(trimmed))
      module_name = "Mensch.SampleDb.Generated#{module_piece}"
      file_name = "lib/mensch/sample_db/generated_#{slugify(trimmed)}.ex"
      {:ok, module_name, file_name}
    end
  end

  defp write_export_module(module_name, file_name, %SampleDefinition{} = sample) do
    module_name = normalize_module_name(module_name)
    sample_context = Map.fetch!(sample, :sample_context)
    sample_entries_literal = sample.sample_entries |> inspect_literal() |> indent_multiline(6)

    total_length_bars_line =
      if is_integer(sample.total_length_bars) and sample.total_length_bars >= 0 do
        "\n      total_length_bars: #{sample.total_length_bars},"
      else
        ""
      end

    total_length_mbeats_line =
      if is_integer(sample.total_length_mbeats) and sample.total_length_mbeats >= 0 do
        "\n      total_length_mbeats: #{sample.total_length_mbeats},"
      else
        ""
      end

    blueprint_meta_line =
      if is_map(sample.blueprint_meta) do
        "\n      blueprint_meta: #{inspect_literal(sample.blueprint_meta)},"
      else
        ""
      end

    module_body =
      """
      defmodule #{module_name} do
        @moduledoc false

        alias Mensch.SampleContext
        alias Mensch.SampleDefinition

        @behaviour Mensch.SampleDefinition.Provider

        @spec sample(pos_integer()) :: SampleDefinition.t()
        def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
          %SampleDefinition{
            id: #{inspect(sample.id)},
            created_at: #{inspect(sample.created_at)},
            folder: #{inspect(sample.folder)},
            name: #{inspect(sample.name)},#{total_length_bars_line}#{total_length_mbeats_line}#{blueprint_meta_line}
            sample_context:
              SampleContext.new!(%{
                bpm: #{sample_context.bpm},
                time_signature: #{inspect(sample_context.time_signature)},
                frame_mbeats: frame_mbeats
              }),
            sample_entries: #{sample_entries_literal}
          }
        end
      end
      """

    File.write!(file_name, module_body)
    :ok
  end

  defp normalize_module_name(module_name) when is_atom(module_name) do
    module_name
    |> Module.split()
    |> Enum.join(".")
  end

  defp normalize_module_name(module_name) when is_binary(module_name), do: module_name

  defp inspect_literal(term) do
    inspect(term,
      pretty: true,
      limit: :infinity,
      charlists: :as_lists,
      width: 98
    )
  end

  defp indent_multiline(value, spaces) when is_binary(value) and is_integer(spaces) and spaces >= 0 do
    indent = String.duplicate(" ", spaces)

    value
    |> String.split("\n")
    |> Enum.join("\n" <> indent)
  end

  defp module_for_generated_file(file_path) when is_binary(file_path) do
    file_path
    |> Path.basename(".ex")
    |> Macro.camelize()
    |> then(&Module.concat([Mensch, SampleDb, &1]))
  end

  defp ensure_loaded(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, loaded} -> {:ok, loaded}
      {:error, reason} -> {:error, "could not load #{inspect(module)}: #{inspect(reason)}"}
    end
  end

  defp maybe_register_module(_module_name, false), do: :ok

  defp maybe_register_module(module_name, true) do
    sample_db_path = "lib/mensch/sample_db.ex"
    content = File.read!(sample_db_path)
    module_alias = module_name |> String.split(".") |> List.last()
    alias_line = "  alias #{module_name}\n"
    sample_line = "    #{module_alias}.sample(@default_frame_mbeats),\n"

    content =
      if String.contains?(content, alias_line) do
        content
      else
        String.replace(
          content,
          "\n  @default_frame_mbeats",
          "\n#{alias_line}\n  @default_frame_mbeats"
        )
      end

    content =
      if String.contains?(content, sample_line) do
        content
      else
        Regex.replace(
          ~r/@samples \[\n(.*?)\n  \]/ms,
          content,
          fn _, body ->
            normalized_body = ensure_samples_body_trailing_comma(body)
            "@samples [\n#{normalized_body}\n#{sample_line}  ]"
          end,
          global: false
        )
      end

    File.write!(sample_db_path, content)
    :ok
  end

  defp ensure_samples_body_trailing_comma(body) when is_binary(body) do
    lines = String.split(body, "\n")

    last_content_index =
      lines
      |> Enum.with_index()
      |> Enum.reduce(nil, fn {line, idx}, acc ->
        if String.trim(line) == "", do: acc, else: idx
      end)

    case last_content_index do
      nil ->
        body

      idx ->
        List.update_at(lines, idx, fn line ->
          trimmed = String.trim_trailing(line)
          if String.ends_with?(trimmed, ","), do: trimmed, else: trimmed <> ","
        end)
        |> Enum.join("\n")
    end
  end

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "sample"
      slug -> slug
    end
  end
end
