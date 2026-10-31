defmodule Mensch.Harmony.ChordProgression do
  @moduledoc """
  Domain struct for chord progression pipeline data.
  """

  alias Mensch.Harmony.ChordSpec

  @enforce_keys [:name, :description, :chords]
  defstruct name: "", description: "", chords: []

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          chords: [ChordSpec.t()]
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    attrs_map =
      case attrs do
        %__MODULE__{} = progression -> Map.from_struct(progression)
        _ -> attrs
      end

    progression = struct(__MODULE__, attrs_map)

    cond do
      not is_binary(progression.name) ->
        {:error, {:invalid_name, progression.name}}

      not is_binary(progression.description) ->
        {:error, {:invalid_description, progression.description}}

      not is_list(progression.chords) ->
        {:error, {:invalid_chords, progression.chords}}

      not Enum.all?(progression.chords, &match?(%ChordSpec{}, &1)) ->
        {:error, {:invalid_chords, progression.chords}}

      true ->
        {:ok, progression}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, progression} -> progression
      {:error, reason} -> raise ArgumentError, "invalid chord progression: #{inspect(reason)}"
    end
  end
end
