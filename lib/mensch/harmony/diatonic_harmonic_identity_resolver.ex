defmodule Mensch.Harmony.DiatonicHarmonicIdentityResolver do
  @moduledoc """
  Builds diatonic `%Mensch.Harmony.ChordSpec{}` values from a scale tonic, mode, and degree.

  Degree is represented as an integer from 1 to 7 and is interpreted within the
  selected mode.

  Supported modes:

  * `:major`
  * `:natural_minor`
  * `:harmonic_minor`

  Supported chord forms:

  * `:triad` (default)
  * `:seventh`
  * `:add6`
  * `:six_nine`
  * `:ninth`
  * `:eleventh`
  * `:thirteenth`

  This module only decides harmonic identity (`root` + `quality`).
  Rendering concerns (`octave`, `inversion`, `voicing`, `foreign_bass`) are
  accepted from caller arguments and passed through unchanged.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.HarmonicIdentity

  @type mode :: :major | :natural_minor | :harmonic_minor
  @type chord_kind ::
          :triad | :seventh | :add6 | :six_nine | :ninth | :eleventh | :thirteenth

  @major_scale_intervals [0, 2, 4, 5, 7, 9, 11]
  @natural_minor_scale_intervals [0, 2, 3, 5, 7, 8, 10]
  @harmonic_minor_scale_intervals [0, 2, 3, 5, 7, 8, 11]

  @major_triad_qualities [:maj, :min, :min, :maj, :maj, :min, :dim]
  @natural_minor_triad_qualities [:min, :dim, :maj, :min, :min, :maj, :maj]
  @harmonic_minor_triad_qualities [:min, :dim, :aug, :min, :maj, :maj, :dim]

  @major_seventh_qualities [:maj7, :min7, :min7, :maj7, :dom7, :min7, :half_dim]
  @natural_minor_seventh_qualities [:min7, :half_dim, :maj7, :min7, :min7, :maj7, :dom7]
  @harmonic_minor_seventh_qualities [
    :min_maj7,
    :half_dim,
    :maj7_sharp5,
    :min7,
    :dom7,
    :maj7,
    :dim7
  ]

  @major_add6_qualities [:maj6, :min6, :min6, :maj6, :maj6, :min6, nil]
  @natural_minor_add6_qualities [:min6, nil, :maj6, :min6, :min6, :maj6, :maj6]
  @harmonic_minor_add6_qualities [:min6, nil, nil, :min6, :maj6, :maj6, nil]

  @major_six_nine_qualities [:six_nine, nil, nil, :six_nine, :six_nine, nil, nil]
  @natural_minor_six_nine_qualities [nil, nil, :six_nine, nil, nil, :six_nine, :six_nine]
  @harmonic_minor_six_nine_qualities [nil, nil, nil, nil, :six_nine, :six_nine, nil]

  @major_ninth_qualities [:maj9, :min9, :min9, :maj9, :dom9, :min9, nil]
  @natural_minor_ninth_qualities [:min9, nil, :maj9, :min9, :min9, :maj9, :dom9]
  @harmonic_minor_ninth_qualities [nil, nil, nil, :min9, :dom9, :maj9, nil]

  @major_eleventh_qualities [:maj11, :min11, :min11, :maj11, nil, :min11, nil]
  @natural_minor_eleventh_qualities [:min11, nil, :maj11, :min11, :min11, :maj11, nil]
  @harmonic_minor_eleventh_qualities [nil, nil, nil, :min11, nil, :maj11, nil]

  @major_thirteenth_qualities [nil, nil, nil, nil, :dom13, nil, nil]
  @natural_minor_thirteenth_qualities [nil, nil, nil, nil, nil, nil, :dom13]
  @harmonic_minor_thirteenth_qualities [nil, nil, nil, nil, :dom13, nil, nil]

  @spec build(map(), integer(), keyword() | map()) :: {:ok, ChordSpec.t()} | {:error, term()}
  def build(scale, degree, opts \\ [])

  def build(scale, degree, opts) when is_map(scale) do
    opts = normalize_opts(opts)

    with {:ok, tonic} <- validate_tonic(Map.get(scale, :tonic)),
         {:ok, mode} <- validate_mode(Map.get(scale, :mode)),
         {:ok, degree_index} <- validate_degree(degree),
         {:ok, chord_kind} <- validate_chord_kind(Map.get(opts, :chord_kind, :triad)),
         {:ok, root} <- degree_root(tonic, mode, degree_index),
         {:ok, quality} <- quality_for(mode, chord_kind, degree_index),
         {:ok, attrs} <- chord_attrs_for(root, quality, opts),
         {:ok, spec} <- ChordSpec.new(attrs) do
      {:ok, spec}
    end
  end

  def build(_scale, _degree, _opts), do: {:error, :invalid_scale}

  @spec build!(map(), integer(), keyword() | map()) :: ChordSpec.t()
  def build!(scale, degree, opts \\ [])

  def build!(scale, degree, opts) do
    case build(scale, degree, opts) do
      {:ok, spec} ->
        spec

      {:error, reason} ->
        raise ArgumentError, "invalid diatonic chord build request: #{inspect(reason)}"
    end
  end

  @spec scale_modes() :: [mode()]
  def scale_modes, do: [:major, :natural_minor, :harmonic_minor]

  @spec chord_kinds() :: [chord_kind()]
  def chord_kinds, do: [:triad, :seventh, :add6, :six_nine, :ninth, :eleventh, :thirteenth]

  defp chord_attrs_for(root, quality, opts) do
    with {:ok, octave} <- required_integer_opt(opts, :octave),
         {:ok, inversion} <- required_integer_opt(opts, :inversion) do
      attrs =
        %{
          harmonic_identity: %HarmonicIdentity{root: root, quality: quality},
          octave: octave,
          inversion: inversion
        }
        |> maybe_put_voicing(opts)
        |> maybe_put_foreign_bass(opts)

      {:ok, attrs}
    end
  end

  defp maybe_put_voicing(attrs, opts) do
    case Map.fetch(opts, :voicing) do
      {:ok, voicing} -> Map.put(attrs, :voicing, voicing)
      :error -> attrs
    end
  end

  defp maybe_put_foreign_bass(attrs, opts) do
    case Map.fetch(opts, :foreign_bass) do
      {:ok, foreign_bass} -> Map.put(attrs, :foreign_bass, foreign_bass)
      :error -> attrs
    end
  end

  defp quality_for(mode, chord_kind, degree_index) do
    quality =
      case {mode, chord_kind} do
        {:major, :triad} ->
          Enum.at(@major_triad_qualities, degree_index)

        {:natural_minor, :triad} ->
          Enum.at(@natural_minor_triad_qualities, degree_index)

        {:harmonic_minor, :triad} ->
          Enum.at(@harmonic_minor_triad_qualities, degree_index)

        {:major, :seventh} ->
          Enum.at(@major_seventh_qualities, degree_index)

        {:natural_minor, :seventh} ->
          Enum.at(@natural_minor_seventh_qualities, degree_index)

        {:harmonic_minor, :seventh} ->
          Enum.at(@harmonic_minor_seventh_qualities, degree_index)

        {:major, :add6} ->
          Enum.at(@major_add6_qualities, degree_index)

        {:natural_minor, :add6} ->
          Enum.at(@natural_minor_add6_qualities, degree_index)

        {:harmonic_minor, :add6} ->
          Enum.at(@harmonic_minor_add6_qualities, degree_index)

        {:major, :six_nine} ->
          Enum.at(@major_six_nine_qualities, degree_index)

        {:natural_minor, :six_nine} ->
          Enum.at(@natural_minor_six_nine_qualities, degree_index)

        {:harmonic_minor, :six_nine} ->
          Enum.at(@harmonic_minor_six_nine_qualities, degree_index)

        {:major, :ninth} ->
          Enum.at(@major_ninth_qualities, degree_index)

        {:natural_minor, :ninth} ->
          Enum.at(@natural_minor_ninth_qualities, degree_index)

        {:harmonic_minor, :ninth} ->
          Enum.at(@harmonic_minor_ninth_qualities, degree_index)

        {:major, :eleventh} ->
          Enum.at(@major_eleventh_qualities, degree_index)

        {:natural_minor, :eleventh} ->
          Enum.at(@natural_minor_eleventh_qualities, degree_index)

        {:harmonic_minor, :eleventh} ->
          Enum.at(@harmonic_minor_eleventh_qualities, degree_index)

        {:major, :thirteenth} ->
          Enum.at(@major_thirteenth_qualities, degree_index)

        {:natural_minor, :thirteenth} ->
          Enum.at(@natural_minor_thirteenth_qualities, degree_index)

        {:harmonic_minor, :thirteenth} ->
          Enum.at(@harmonic_minor_thirteenth_qualities, degree_index)
      end

    case quality do
      nil ->
        {:error,
         {:unsupported_chord_kind_for_degree,
          %{mode: mode, chord_kind: chord_kind, degree: degree_index + 1}}}

      value ->
        {:ok, value}
    end
  end

  defp degree_root(tonic, mode, degree_index) do
    tonic_semitone = ChordSpec.pitch_class_to_semitone(tonic)
    interval = Enum.at(scale_intervals_for_mode(mode), degree_index)
    semitone = rem(tonic_semitone + interval, 12)
    spelling = preferred_spelling(tonic)
    {root, _octave} = ChordSpec.note_name(semitone, spelling)
    {:ok, root}
  end

  defp scale_intervals_for_mode(:major), do: @major_scale_intervals
  defp scale_intervals_for_mode(:natural_minor), do: @natural_minor_scale_intervals
  defp scale_intervals_for_mode(:harmonic_minor), do: @harmonic_minor_scale_intervals

  defp preferred_spelling(tonic) do
    semitone = ChordSpec.pitch_class_to_semitone(tonic)

    cond do
      tonic in [:d_flat, :e_flat, :g_flat, :a_flat, :b_flat, :c_flat, :f_flat] -> :flat
      tonic in [:c_sharp, :d_sharp, :f_sharp, :g_sharp, :a_sharp, :b_sharp, :e_sharp] -> :sharp
      semitone in [1, 3, 6, 8, 10] -> :flat
      true -> :sharp
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: Enum.into(opts, %{})
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(_opts), do: %{}

  defp required_integer_opt(opts, key) do
    case Map.fetch(opts, key) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_opt, key, value}}
      :error -> {:error, {:missing_opt, key}}
    end
  end

  defp validate_tonic(tonic) when is_atom(tonic) do
    if is_nil(ChordSpec.pitch_class_to_semitone(tonic)) do
      {:error, {:invalid_tonic, tonic}}
    else
      {:ok, tonic}
    end
  end

  defp validate_tonic(tonic), do: {:error, {:invalid_tonic, tonic}}

  defp validate_mode(mode) when mode in [:major, :natural_minor, :harmonic_minor], do: {:ok, mode}
  defp validate_mode(mode), do: {:error, {:invalid_mode, mode}}

  defp validate_degree(degree) when is_integer(degree) and degree >= 1 and degree <= 7,
    do: {:ok, degree - 1}

  defp validate_degree(degree), do: {:error, {:invalid_degree, degree}}

  defp validate_chord_kind(chord_kind)
       when chord_kind in [:triad, :seventh, :add6, :six_nine, :ninth, :eleventh, :thirteenth],
       do: {:ok, chord_kind}

  defp validate_chord_kind(chord_kind), do: {:error, {:invalid_chord_kind, chord_kind}}
end
