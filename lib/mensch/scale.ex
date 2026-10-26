defmodule Mensch.Scale do
  @moduledoc """
  Public API for independent scale engine operations.
  """

  alias Mensch.Scale.ModeResolver
  alias Mensch.Scale.ScaleGenerator
  alias Mensch.Scale.ScaleRegistry
  alias Mensch.Scale.ScaleSpec

  @spec registry() :: [map()]
  def registry, do: ScaleRegistry.all()

  @spec build_scale(atom(), atom(), pos_integer() | nil) ::
          {:ok, ScaleSpec.t()} | {:error, term()}
  def build_scale(tonic, family, mode) when is_atom(tonic) and is_atom(family) do
    with {:ok, _entry} <- ScaleRegistry.fetch(family),
         {:ok, resolved} <- ModeResolver.resolve(family, mode) do
      ScaleSpec.new(%{
        tonic: tonic,
        family: family,
        mode: resolved.mode,
        name: resolved.name,
        intervals: resolved.intervals
      })
    end
  end

  @spec notes(ScaleSpec.t()) :: {:ok, [String.t()]} | {:error, term()}
  defdelegate notes(scale_spec), to: ScaleGenerator

  @spec pitch_classes(ScaleSpec.t()) :: {:ok, [integer()]} | {:error, term()}
  defdelegate pitch_classes(scale_spec), to: ScaleGenerator

  @spec midi_notes(ScaleSpec.t(), integer(), integer()) :: {:ok, [integer()]} | {:error, term()}
  defdelegate midi_notes(scale_spec, min_note, max_note), to: ScaleGenerator

  @spec tonic_midi_notes(ScaleSpec.t(), integer(), integer()) ::
          {:ok, [integer()]} | {:error, term()}
  defdelegate tonic_midi_notes(scale_spec, min_note, max_note), to: ScaleGenerator

  @spec midi_notes_full_octaves(ScaleSpec.t(), integer(), integer()) ::
          {:ok, [integer()]} | {:error, term()}
  defdelegate midi_notes_full_octaves(scale_spec, min_note, max_note), to: ScaleGenerator
end
