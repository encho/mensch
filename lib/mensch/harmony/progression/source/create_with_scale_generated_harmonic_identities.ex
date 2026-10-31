defmodule Mensch.Harmony.Progression.Source.CreateWithScaleGeneratedHarmonicIdentities do
  @moduledoc """
  Source for creating chords from scale-generated harmonic identities.

  This source mirrors the identity resolution approach used in `/scale-chord-lab`:
  generated scale chords are resolved via `HarmonicIdentityInference.infer/2`,
  which is direct-first with inference fallback.
  """

  alias Mensch.Harmony.ChordProgression
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.HarmonicIdentityInference
  alias Mensch.Scale

  @type opts :: [
          degrees: [integer()],
          scale: %{tonic: ChordSpec.pitch_class(), family: atom(), mode: pos_integer()},
          strategy: atom(),
          shape: atom(),
          spelling_mode: :practical | :strict,
          render_defaults: keyword() | map()
        ]

  @spec source(opts()) :: (-> {:ok, ChordProgression.t()} | {:error, term()})
  def source(opts) when is_list(opts) do
    fn ->
      with {:ok, explicit_degrees} <- fetch_degrees(opts),
           {:ok, scale_args} <- fetch_scale(opts),
           {:ok, scale_spec} <- build_scale_spec(scale_args),
           {:ok, degrees} <- resolve_degrees(explicit_degrees, scale_spec),
           strategy <- Keyword.get(opts, :strategy, :tertian),
           shape <- Keyword.get(opts, :shape, :triad),
           spelling_mode <- Keyword.get(opts, :spelling_mode, :practical),
           :ok <- validate_spelling_mode(spelling_mode),
           render_defaults <- normalize_defaults(Keyword.get(opts, :render_defaults, %{})),
           {:ok, chords} <-
             build_chords(scale_spec, degrees, strategy, shape, spelling_mode, render_defaults) do
        {:ok,
         %ChordProgression{
           name: "Scale-Generated Harmonic Identity Progression",
           description:
             "Generates chords from a scale and resolves harmonic identities via direct-first inference.",
           chords: chords
         }}
      end
    end
  end

  defp fetch_degrees(opts) do
    case Keyword.fetch(opts, :degrees) do
      {:ok, degrees} when is_list(degrees) -> {:ok, degrees}
      :error -> {:ok, nil}
      _ -> {:error, :invalid_degrees}
    end
  end

  defp resolve_degrees(nil, scale_spec), do: {:ok, Enum.to_list(1..scale_size(scale_spec))}

  defp resolve_degrees(degrees, scale_spec) when is_list(degrees) do
    size = scale_size(scale_spec)

    if Enum.all?(degrees, &is_integer/1) and Enum.all?(degrees, &(&1 >= 1 and &1 <= size)) do
      {:ok, degrees}
    else
      {:error, {:invalid_degrees_for_scale, size}}
    end
  end

  defp fetch_scale(opts) do
    case Keyword.fetch(opts, :scale) do
      {:ok, %{tonic: _tonic, family: _family, mode: _mode} = scale} -> {:ok, scale}
      _ -> {:error, :missing_scale}
    end
  end

  defp build_scale_spec(%{tonic: tonic, family: family, mode: mode}) do
    case Scale.build_scale(tonic, family, mode) do
      {:ok, scale_spec} -> {:ok, scale_spec}
      {:error, reason} -> {:error, {:invalid_scale, reason}}
    end
  end

  defp scale_size(%{intervals: intervals}) when is_list(intervals), do: length(intervals)
  defp scale_size(_), do: 7

  defp validate_spelling_mode(spelling_mode) when spelling_mode in [:practical, :strict], do: :ok
  defp validate_spelling_mode(_), do: {:error, :invalid_spelling_mode}

  defp normalize_defaults(defaults) when is_list(defaults), do: Enum.into(defaults, %{})
  defp normalize_defaults(defaults) when is_map(defaults), do: defaults
  defp normalize_defaults(_), do: %{}

  defp build_chords(scale_spec, degrees, strategy, shape, spelling_mode, render_defaults) do
    degrees
    |> Enum.reduce_while({:ok, []}, fn degree, {:ok, acc} ->
      case build_one(scale_spec, degree, strategy, shape, spelling_mode, render_defaults) do
        {:ok, chord_spec} ->
          {:cont, {:ok, acc ++ [chord_spec]}}

        {:error, reason} ->
          {:halt, {:error, {:build_failed, degree, reason}}}
      end
    end)
  end

  defp build_one(scale_spec, degree, strategy, shape, spelling_mode, render_defaults) do
    with {:ok, generated_chord} <-
           Scale.generate_chord(scale_spec, degree, strategy: strategy, shape: shape),
         {:ok, harmonic_identity} <-
           resolve_identity(scale_spec, generated_chord, strategy, shape, degree, spelling_mode),
         {:ok, attrs} <- chord_attrs_for(harmonic_identity, render_defaults),
         {:ok, chord_spec} <- ChordSpec.new(attrs) do
      {:ok, chord_spec}
    end
  end

  defp resolve_identity(scale_spec, generated_chord, strategy, shape, degree, spelling_mode) do
    bass_pitch_class = semitone_to_pitch_class(generated_chord.root_pitch_class)

    case HarmonicIdentityInference.infer(generated_chord.pitch_classes,
           scale_spec: scale_spec,
           spelling_mode: spelling_mode,
           bass_pitch_class: bass_pitch_class,
           preferred_root_pitch_class: generated_chord.root_pitch_class,
           preferred_strategy: strategy,
           preferred_shape: shape,
           preferred_degree: degree
         ) do
      [%{harmonic_identity: harmonic_identity} | _] -> {:ok, harmonic_identity}
      _ -> {:error, :unresolved_identity}
    end
  end

  defp chord_attrs_for(harmonic_identity, render_defaults) do
    with {:ok, octave} <- fetch_integer_default(render_defaults, :octave),
         {:ok, inversion} <- fetch_integer_default(render_defaults, :inversion) do
      attrs =
        %{
          harmonic_identity: harmonic_identity,
          octave: octave,
          inversion: inversion
        }
        |> maybe_put_voicing(render_defaults)
        |> maybe_put_foreign_bass(render_defaults)

      {:ok, attrs}
    end
  end

  defp fetch_integer_default(defaults, key) do
    case Map.fetch(defaults, key) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_render_default, key, value}}
      :error -> {:error, {:missing_render_default, key}}
    end
  end

  defp maybe_put_voicing(attrs, defaults) do
    case Map.fetch(defaults, :voicing) do
      {:ok, voicing} -> Map.put(attrs, :voicing, voicing)
      :error -> attrs
    end
  end

  defp maybe_put_foreign_bass(attrs, defaults) do
    case Map.fetch(defaults, :foreign_bass) do
      {:ok, foreign_bass} -> Map.put(attrs, :foreign_bass, foreign_bass)
      :error -> attrs
    end
  end

  defp semitone_to_pitch_class(0), do: :c
  defp semitone_to_pitch_class(1), do: :c_sharp
  defp semitone_to_pitch_class(2), do: :d
  defp semitone_to_pitch_class(3), do: :d_sharp
  defp semitone_to_pitch_class(4), do: :e
  defp semitone_to_pitch_class(5), do: :f
  defp semitone_to_pitch_class(6), do: :f_sharp
  defp semitone_to_pitch_class(7), do: :g
  defp semitone_to_pitch_class(8), do: :g_sharp
  defp semitone_to_pitch_class(9), do: :a
  defp semitone_to_pitch_class(10), do: :a_sharp
  defp semitone_to_pitch_class(11), do: :b
end
