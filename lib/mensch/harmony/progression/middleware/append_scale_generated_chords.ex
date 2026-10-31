defmodule Mensch.Harmony.Progression.Middleware.AppendScaleGeneratedChords do
  @moduledoc """
  Appends scale-generated harmonic-identity chords to an existing progression.
  """

  alias Mensch.Harmony.ChordProgression
  alias Mensch.Harmony.Progression.Source.CreateWithScaleGeneratedHarmonicIdentities

  @type opts :: keyword()

  @spec middleware(opts()) :: (ChordProgression.t() ->
                                 {:ok, ChordProgression.t()} | {:error, term()})
  def middleware(opts \\ []) when is_list(opts) do
    source = CreateWithScaleGeneratedHarmonicIdentities.source(opts)

    fn progression ->
      append_scale_generated_chords(progression, source)
    end
  end

  defp append_scale_generated_chords(%ChordProgression{} = progression, source)
       when is_function(source, 0) do
    case source.() do
      {:ok, %ChordProgression{} = generated} ->
        {:ok, %{progression | chords: progression.chords ++ generated.chords}}

      {:error, reason} ->
        {:error, {:scale_generation_failed, reason}}

      other ->
        {:error, {:invalid_source_result, other}}
    end
  end

  defp append_scale_generated_chords(_progression, _source), do: {:error, :invalid_progression}
end
