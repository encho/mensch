defmodule Mensch.SampleBlueprints.Registry do
  @moduledoc """
  Explicit registry for available sample blueprint modules.
  """

  alias Mensch.SampleBlueprints.DynamicVoicing
  alias Mensch.SampleBlueprints.Strum

  @blueprint_modules [DynamicVoicing, Strum]

  @legacy_id_aliases %{
    "dynamic_voicing" => DynamicVoicing.id(),
    "strum" => Strum.id()
  }

  @spec modules() :: [module()]
  def modules, do: @blueprint_modules

  @spec default_blueprint_id() :: String.t()
  def default_blueprint_id do
    @blueprint_modules
    |> List.first()
    |> apply(:id, [])
  end

  @spec available_blueprints() :: [%{id: String.t(), label: String.t()}]
  def available_blueprints do
    Enum.map(@blueprint_modules, fn module ->
      %{id: module.id(), label: module.label()}
    end)
  end

  @spec fetch(String.t() | atom()) :: {:ok, module()} | {:error, String.t()}
  def fetch(id) when is_atom(id), do: fetch(Atom.to_string(id))

  def fetch(id) when is_binary(id) do
    normalized_id = Map.get(@legacy_id_aliases, id, id)

    case Enum.find(@blueprint_modules, &(apply(&1, :id, []) == normalized_id)) do
      nil -> {:error, "invalid blueprint_id"}
      module -> {:ok, module}
    end
  end
end
