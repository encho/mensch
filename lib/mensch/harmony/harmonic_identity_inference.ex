defmodule Mensch.Harmony.HarmonicIdentityInference do
  @moduledoc """
  Infers and ranks harmonic identities from a set of notes.

  The result list is always sorted from best match to worst match and includes
  a quality score in the range 0..100.

  If a scale spec is provided, matches are additionally scored for scale
  consistency.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.HarmonicIdentity
  alias Mensch.Harmony.DirectHarmonicIdentityResolver
  alias Mensch.Scale.ScaleGenerator
  alias Mensch.Scale.ScaleSpec

  @type candidate_match :: %{
          required(:harmonic_identity) => HarmonicIdentity.t(),
          required(:quality) => float(),
          required(:score_raw) => number(),
          required(:matching) => %{
            required(:intersection) => non_neg_integer(),
            required(:expected) => non_neg_integer(),
            required(:observed) => non_neg_integer()
          },
          required(:reasons) => [String.t()]
        }

  @type infer_opts :: [
          scale_spec: ScaleSpec.t() | nil,
          spelling_mode: :practical | :strict,
          bass_pitch_class: ChordSpec.pitch_class() | nil,
          preferred_root_pitch_class: integer() | nil,
          preferred_strategy: atom() | nil,
          preferred_shape: atom() | nil,
          preferred_degree: pos_integer() | nil
        ]

  @root_prior_bonus 18
  @strategy_shape_prior_bonus 12
  @degree_prior_bonus 6
  @slash_difference_bonus 1
  @slash_unison_penalty 2

  @spec infer([integer()], infer_opts()) :: [candidate_match()]
  def infer(note_numbers_or_pitch_classes, opts \\ [])

  def infer(note_numbers_or_pitch_classes, opts) when is_list(note_numbers_or_pitch_classes) do
    observed_pitch_classes = normalize_pitch_classes(note_numbers_or_pitch_classes)

    case observed_pitch_classes do
      [] ->
        []

      pcs ->
        scale_spec = Keyword.get(opts, :scale_spec)
        spelling_mode = Keyword.get(opts, :spelling_mode, :practical)
        explicit_foreign_bass = Keyword.get(opts, :bass_pitch_class)
        spelling_map = spelling_map(scale_spec, spelling_mode)

        foreign_bass =
          resolve_foreign_bass_option(note_numbers_or_pitch_classes, explicit_foreign_bass)

        foreign_bass_pc = pitch_class_to_semitone_or_nil(foreign_bass)

        preferred_root_pitch_class =
          normalize_preferred_root(Keyword.get(opts, :preferred_root_pitch_class))

        preferred_strategy = Keyword.get(opts, :preferred_strategy)
        preferred_shape = Keyword.get(opts, :preferred_shape)
        preferred_degree = Keyword.get(opts, :preferred_degree)

        priors = %{
          preferred_root_pitch_class: preferred_root_pitch_class,
          preferred_strategy: preferred_strategy,
          preferred_shape: preferred_shape,
          preferred_degree: preferred_degree
        }

        root_candidates = 0..11

        root_candidates
        |> Enum.flat_map(fn root_pc ->
          root = spell_pitch_class(root_pc, spelling_map)

          Enum.map(ChordSpec.qualities(), fn quality ->
            score_candidate(
              pcs,
              root,
              root_pc,
              quality,
              foreign_bass_pc,
              spelling_map,
              scale_spec,
              priors
            )
          end)
        end)
        |> Enum.map(&Map.put_new(&1, :source, :inferred))
        |> Enum.sort_by(fn entry ->
          {-entry.quality, -entry.score_raw, root_sort_key(entry.harmonic_identity.root)}
        end)
        |> maybe_prepend_direct_identity(pcs, opts)
    end
  end

  def infer(_notes, _opts), do: []

  defp maybe_prepend_direct_identity(inferred, observed_pitch_classes, opts)
       when is_list(inferred) and is_list(observed_pitch_classes) do
    scale_spec = Keyword.get(opts, :scale_spec)
    strategy = Keyword.get(opts, :preferred_strategy)
    shape = Keyword.get(opts, :preferred_shape)
    degree = Keyword.get(opts, :preferred_degree)

    root_pc =
      opts
      |> Keyword.get(:preferred_root_pitch_class)
      |> normalize_preferred_root()

    spelling_mode = Keyword.get(opts, :spelling_mode, :practical)

    with %ScaleSpec{} <- scale_spec,
         strategy when is_atom(strategy) <- strategy,
         shape when is_atom(shape) <- shape,
         degree when is_integer(degree) and degree > 0 <- degree,
         root_pc when is_integer(root_pc) <- root_pc,
         {:ok, identity} <-
           DirectHarmonicIdentityResolver.resolve(
             scale_spec,
             %{root_pitch_class: root_pc, pitch_classes: observed_pitch_classes},
             strategy: strategy,
             shape: shape,
             degree: degree,
             spelling_mode: spelling_mode
           ) do
      direct_match = %{
        harmonic_identity: identity,
        quality: 100.0,
        score_raw: :direct,
        matching: %{intersection: 0, expected: 0, observed: 0},
        reasons: ["source=direct"],
        source: :direct
      }

      rest =
        Enum.reject(inferred, fn match ->
          harmonic_identity_equal?(match.harmonic_identity, identity)
        end)

      [direct_match | rest]
    else
      _ -> inferred
    end
  end

  defp maybe_prepend_direct_identity(inferred, _observed_pitch_classes, _opts), do: inferred

  defp harmonic_identity_equal?(left, right)
       when is_struct(left, HarmonicIdentity) and is_struct(right, HarmonicIdentity) do
    left.root == right.root and left.quality == right.quality and
      left.foreign_bass == right.foreign_bass
  end

  defp harmonic_identity_equal?(_left, _right), do: false

  defp score_candidate(
         observed_pcs,
         root,
         root_pc,
         quality,
         foreign_bass_pc,
         spelling_map,
         scale_spec,
         priors
       ) do
    quality_pcs = quality_pitch_classes(root_pc, quality)

    observed_set = MapSet.new(observed_pcs)
    expected_set = MapSet.new(quality_pcs)
    intersection = MapSet.intersection(observed_set, expected_set) |> MapSet.size()
    expected_size = MapSet.size(expected_set)
    observed_size = MapSet.size(observed_set)

    missing_count = expected_size - intersection
    extra_count = observed_size - intersection

    root_present_bonus = if MapSet.member?(observed_set, root_pc), do: 10, else: 0

    effective_foreign_bass =
      resolve_foreign_bass_for_candidate(foreign_bass_pc, expected_set, spelling_map)

    slash_adjustment = slash_adjustment(effective_foreign_bass, root)

    scale_adjustment = scale_adjustment(expected_set, scale_spec)
    prior_adjustment = prior_adjustment(priors, root_pc, quality)

    score_raw =
      intersection * 20 +
        root_present_bonus +
        slash_adjustment +
        scale_adjustment +
        prior_adjustment -
        missing_count * 11 -
        extra_count * 6

    quality_score = normalize_score(score_raw)

    harmonic_identity = %HarmonicIdentity{
      root: root,
      quality: quality,
      foreign_bass: effective_foreign_bass
    }

    %{
      harmonic_identity: harmonic_identity,
      quality: quality_score,
      score_raw: score_raw,
      matching: %{intersection: intersection, expected: expected_size, observed: observed_size},
      reasons:
        reasons(
          intersection,
          expected_size,
          observed_size,
          missing_count,
          extra_count,
          root_present_bonus,
          slash_adjustment,
          scale_adjustment,
          prior_adjustment,
          effective_foreign_bass,
          root
        )
    }
  end

  defp normalize_pitch_classes(values) do
    values
    |> Enum.filter(&is_integer/1)
    |> Enum.map(&rem(&1 + 120, 12))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp resolve_foreign_bass_option(_note_numbers_or_pitch_classes, explicit_foreign_bass)
       when is_atom(explicit_foreign_bass),
       do: explicit_foreign_bass

  defp resolve_foreign_bass_option(note_numbers_or_pitch_classes, _explicit_foreign_bass) do
    note_numbers_or_pitch_classes
    |> Enum.filter(&is_integer/1)
    |> Enum.sort()
    |> List.first()
    |> case do
      nil -> nil
      min_value -> semitone_to_pitch_class(rem(min_value + 120, 12))
    end
  end

  defp quality_pitch_classes(root_pc, quality) do
    quality
    |> ChordSpec.quality_tones()
    |> Enum.map(&ChordSpec.tone_interval/1)
    |> Enum.map(&rem(root_pc + &1, 12))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp scale_adjustment(_expected_set, nil), do: 0

  defp scale_adjustment(expected_set, %ScaleSpec{tonic: tonic, intervals: intervals}) do
    tonic_pc = ChordSpec.pitch_class_to_semitone(tonic)

    scale_pcs =
      intervals
      |> Enum.map(&rem(tonic_pc + &1, 12))
      |> MapSet.new()

    in_scale = expected_set |> MapSet.intersection(scale_pcs) |> MapSet.size()
    out_scale = MapSet.size(expected_set) - in_scale

    in_scale * 3 - out_scale * 4
  end

  defp normalize_score(score_raw) do
    # Logistic-like clamp for stable 0..100 quality numbers.
    normalized = 100.0 / (1.0 + :math.exp(-score_raw / 15.0))
    Float.round(normalized, 2)
  end

  defp normalize_preferred_root(nil), do: nil

  defp normalize_preferred_root(value) when is_integer(value),
    do: rem(value + 120, 12)

  defp normalize_preferred_root(_value), do: nil

  defp pitch_class_to_semitone_or_nil(nil), do: nil

  defp pitch_class_to_semitone_or_nil(pitch_class) when is_atom(pitch_class),
    do: ChordSpec.pitch_class_to_semitone(pitch_class)

  defp resolve_foreign_bass_for_candidate(nil, _expected_set, _spelling_map), do: nil

  defp resolve_foreign_bass_for_candidate(foreign_bass_pc, expected_set, spelling_map)
       when is_integer(foreign_bass_pc) do
    if MapSet.member?(expected_set, foreign_bass_pc) do
      nil
    else
      spell_pitch_class(foreign_bass_pc, spelling_map)
    end
  end

  defp spelling_map(nil, _spelling_mode), do: %{}

  defp spelling_map(
         %ScaleSpec{tonic: tonic, intervals: intervals} = scale_spec,
         spelling_mode
       )
       when spelling_mode in [:practical, :strict] do
    tonic_pc = ChordSpec.pitch_class_to_semitone(tonic)

    with {:ok, note_names} <- ScaleGenerator.notes(scale_spec, spelling_mode) do
      note_names
      |> Enum.zip(intervals)
      |> Enum.reduce(%{}, fn {note_name, interval}, acc ->
        semitone = rem(tonic_pc + interval, 12)

        case note_name_to_pitch_class_atom(note_name) do
          {:ok, pitch_class} -> Map.put_new(acc, semitone, pitch_class)
          :error -> acc
        end
      end)
    else
      _ -> %{}
    end
  end

  defp spell_pitch_class(semitone, spelling_map) when is_integer(semitone) do
    case Map.get(spelling_map, semitone) do
      pitch_class when is_atom(pitch_class) and not is_nil(pitch_class) -> pitch_class
      _ -> semitone_to_pitch_class(semitone)
    end
  end

  defp note_name_to_pitch_class_atom(note_name) when is_binary(note_name) do
    case String.downcase(note_name) do
      "c" -> {:ok, :c}
      "b#" -> {:ok, :b_sharp}
      "cb" -> {:ok, :c_flat}
      "c#" -> {:ok, :c_sharp}
      "db" -> {:ok, :d_flat}
      "d" -> {:ok, :d}
      "d#" -> {:ok, :d_sharp}
      "eb" -> {:ok, :e_flat}
      "e" -> {:ok, :e}
      "fb" -> {:ok, :f_flat}
      "e#" -> {:ok, :e_sharp}
      "f" -> {:ok, :f}
      "f#" -> {:ok, :f_sharp}
      "gb" -> {:ok, :g_flat}
      "g" -> {:ok, :g}
      "g#" -> {:ok, :g_sharp}
      "ab" -> {:ok, :a_flat}
      "a" -> {:ok, :a}
      "a#" -> {:ok, :a_sharp}
      "bb" -> {:ok, :b_flat}
      "b" -> {:ok, :b}
      _ -> :error
    end
  end

  defp note_name_to_pitch_class_atom(_note_name), do: :error

  defp slash_adjustment(nil, _root), do: 0

  defp slash_adjustment(foreign_bass, root) when foreign_bass == root,
    do: @slash_unison_penalty

  defp slash_adjustment(_foreign_bass, _root), do: @slash_difference_bonus

  defp prior_adjustment(priors, root_pc, quality) do
    root_prior_adjustment(priors.preferred_root_pitch_class, root_pc) +
      strategy_shape_prior_adjustment(priors.preferred_strategy, priors.preferred_shape, quality) +
      degree_prior_adjustment(priors.preferred_degree, quality)
  end

  defp root_prior_adjustment(nil, _root_pc), do: 0

  defp root_prior_adjustment(preferred_root_pc, root_pc) when preferred_root_pc == root_pc,
    do: @root_prior_bonus

  defp root_prior_adjustment(_preferred_root_pc, _root_pc), do: 0

  defp strategy_shape_prior_adjustment(:tertian, shape, quality)
       when shape in [:triad, :seventh, :ninth, :eleventh, :thirteenth, :add6, :six_nine] do
    if quality_matches_shape?(quality, shape), do: @strategy_shape_prior_bonus, else: 0
  end

  defp strategy_shape_prior_adjustment(_strategy, _shape, _quality), do: 0

  defp degree_prior_adjustment(nil, _quality), do: 0

  defp degree_prior_adjustment(degree, quality) when is_integer(degree) do
    if degree == 1 and quality in [:maj, :min, :maj7, :min7], do: @degree_prior_bonus, else: 0
  end

  defp degree_prior_adjustment(_degree, _quality), do: 0

  defp quality_matches_shape?(quality, :triad),
    do: quality in [:maj, :min, :dim, :aug, :sus2, :sus4]

  defp quality_matches_shape?(quality, :seventh),
    do: quality in [:maj7, :min7, :dom7, :half_dim, :dim7, :min_maj7, :maj7_sharp5]

  defp quality_matches_shape?(quality, :ninth),
    do:
      quality in [
        :maj9,
        :min9,
        :dom9,
        :maj7_add_sharp9,
        :dim7_flat9,
        :min_maj9,
        :half_dim_flat9,
        :maj7_sharp5_9,
        :dom7_flat9
      ]

  defp quality_matches_shape?(quality, :eleventh), do: quality in [:maj11, :min11]
  defp quality_matches_shape?(quality, :thirteenth), do: quality in [:dom13]
  defp quality_matches_shape?(quality, :add6), do: quality in [:maj6, :min6]
  defp quality_matches_shape?(quality, :six_nine), do: quality in [:six_nine]

  defp reasons(
         intersection,
         expected,
         observed,
         missing,
         extra,
         root_bonus,
         slash_adjustment,
         scale_adjustment,
         prior_adjustment,
         bass_pc,
         root
       ) do
    [
      "intersection=#{intersection}/#{expected}",
      "observed=#{observed}",
      "missing=#{missing}",
      "extra=#{extra}",
      if(root_bonus > 0, do: "root_present", else: "root_absent"),
      "slash_adjustment=#{slash_adjustment}",
      "scale_adjustment=#{scale_adjustment}",
      "prior_adjustment=#{prior_adjustment}",
      slash_reason(bass_pc, root)
    ]
  end

  defp slash_reason(nil, _root), do: "slash=none"
  defp slash_reason(bass_pc, root) when bass_pc == root, do: "slash=unison"
  defp slash_reason(bass_pc, _root), do: "slash=#{ChordSpec.root_label(bass_pc)}"

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

  defp root_sort_key(root) do
    ChordSpec.pitch_class_to_semitone(root) || 999
  end
end
