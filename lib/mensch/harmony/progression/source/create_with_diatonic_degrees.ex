defmodule Mensch.Harmony.Progression.Source.CreateWithDiatonicDegrees do
  @moduledoc """
  Source for creating chords from diatonic degrees.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.DiatonicHarmonicIdentityResolver

  @type opts :: [
          degrees: [integer()],
          scale: %{tonic: ChordSpec.pitch_class(), mode: atom()},
          chord_kind: atom(),
          render_defaults: keyword() | map()
        ]

  @spec source(opts()) :: (-> {:ok, [ChordSpec.t()]} | {:error, term()})
  def source(opts) when is_list(opts) do
    fn ->
      with {:ok, degrees} <- fetch_degrees(opts),
           :ok <- validate_degrees(degrees),
           {:ok, scale} <- fetch_scale(opts),
           chord_kind <- Keyword.get(opts, :chord_kind, :triad),
           render_defaults <- normalize_defaults(Keyword.get(opts, :render_defaults, %{})),
           {:ok, chords} <- build_chords(scale, degrees, chord_kind, render_defaults) do
        {:ok, chords}
      end
    end
  end

  defp fetch_degrees(opts) do
    case Keyword.fetch(opts, :degrees) do
      {:ok, degrees} when is_list(degrees) -> {:ok, degrees}
      _ -> {:error, :missing_degrees}
    end
  end

  defp validate_degrees(degrees) do
    if Enum.all?(degrees, &is_integer/1) and Enum.all?(degrees, &(&1 >= 1 and &1 <= 7)) do
      :ok
    else
      {:error, :invalid_degrees}
    end
  end

  defp fetch_scale(opts) do
    case Keyword.fetch(opts, :scale) do
      {:ok, %{tonic: _tonic, mode: _mode} = scale} -> {:ok, scale}
      _ -> {:error, :missing_scale}
    end
  end

  defp normalize_defaults(defaults) when is_list(defaults), do: Enum.into(defaults, %{})
  defp normalize_defaults(defaults) when is_map(defaults), do: defaults
  defp normalize_defaults(_), do: %{}

  defp build_chords(scale, degrees, chord_kind, render_defaults) do
    opts =
      render_defaults
      |> Map.put(:chord_kind, chord_kind)

    degrees
    |> Enum.reduce_while({:ok, []}, fn degree, {:ok, acc} ->
      case DiatonicHarmonicIdentityResolver.build(scale, degree, opts) do
        {:ok, chord_spec} ->
          {:cont, {:ok, acc ++ [chord_spec]}}

        {:error, reason} ->
          {:halt, {:error, {:build_failed, degree, reason}}}
      end
    end)
  end
end
