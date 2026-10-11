defmodule Mensch.SampleDefinition do
  @moduledoc """
  Canonical typed sample definition used across SampleDb and blueprint exports.
  """

  alias Mensch.SampleContext
  alias Mensch.SampleEntry

  @enforce_keys [:id, :folder, :name, :sample_context, :sample_entries]
  defstruct [
    :id,
    :folder,
    :name,
    :sample_context,
    :sample_entries,
    :total_length_bars,
    :total_length_mbeats,
    :blueprint_meta
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          folder: String.t(),
          name: String.t(),
          sample_context: SampleContext.t(),
          sample_entries: [SampleEntry.t()],
          total_length_bars: non_neg_integer() | nil,
          total_length_mbeats: non_neg_integer() | nil,
          blueprint_meta: map() | nil
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    definition = struct(__MODULE__, attrs)

    cond do
      not is_binary(definition.id) or String.trim(definition.id) == "" ->
        {:error, {:invalid_id, definition.id}}

      not is_binary(definition.folder) or String.trim(definition.folder) == "" ->
        {:error, {:invalid_folder, definition.folder}}

      not is_binary(definition.name) or String.trim(definition.name) == "" ->
        {:error, {:invalid_name, definition.name}}

      not match?(%SampleContext{}, definition.sample_context) ->
        {:error, {:invalid_sample_context, definition.sample_context}}

      not is_list(definition.sample_entries) or
          Enum.any?(definition.sample_entries, &(not match?(%SampleEntry{}, &1))) ->
        {:error, {:invalid_sample_entries, definition.sample_entries}}

      not valid_optional_non_negative_integer?(definition.total_length_bars) ->
        {:error, {:invalid_total_length_bars, definition.total_length_bars}}

      not valid_optional_non_negative_integer?(definition.total_length_mbeats) ->
        {:error, {:invalid_total_length_mbeats, definition.total_length_mbeats}}

      not is_nil(definition.blueprint_meta) and not is_map(definition.blueprint_meta) ->
        {:error, {:invalid_blueprint_meta, definition.blueprint_meta}}

      true ->
        {:ok, definition}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, definition} -> definition
      {:error, reason} -> raise ArgumentError, "invalid sample definition: #{inspect(reason)}"
    end
  end

  defp valid_optional_non_negative_integer?(nil), do: true
  defp valid_optional_non_negative_integer?(value), do: is_integer(value) and value >= 0
end
