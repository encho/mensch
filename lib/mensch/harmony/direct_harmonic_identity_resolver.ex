defmodule Mensch.Harmony.DirectHarmonicIdentityResolver do
  @moduledoc """
  Deterministically resolves harmonic identity directly from generated chord data.

  This resolver is intentionally strict. It returns `:unknown` unless it can map
  the generated chord to exactly one known `ChordSpec` quality.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.HarmonicIdentity
  alias Mensch.Scale.ScaleGenerator
  alias Mensch.Scale.ScaleSpec

  @type opts :: [
          strategy: atom() | nil,
          shape: atom() | nil,
          degree: pos_integer() | nil,
          spelling_mode: :practical | :strict
        ]

  @spec resolve(ScaleSpec.t(), map(), opts()) :: {:ok, HarmonicIdentity.t()} | :unknown
  def resolve(scale_spec, generated_chord, opts \\ [])

  def resolve(%ScaleSpec{} = scale_spec, generated_chord, opts)
      when is_map(generated_chord) do
    strategy = Keyword.get(opts, :strategy)
    shape = Keyword.get(opts, :shape)
    spelling_mode = Keyword.get(opts, :spelling_mode, :practical)

    with :ok <- require_supported_strategy(strategy),
         {:ok, root_pc} <- fetch_integer(generated_chord, :root_pitch_class),
         {:ok, chord_pcs} <- fetch_integer_list(generated_chord, :pitch_classes),
         {:ok, quality} <- resolve_quality(root_pc, chord_pcs, shape),
         {:ok, root_atom} <- resolve_spelled_root(scale_spec, root_pc, spelling_mode) do
      {:ok, %HarmonicIdentity{root: root_atom, quality: quality, foreign_bass: nil}}
    else
      _ -> :unknown
    end
  end

  def resolve(_scale_spec, _generated_chord, _opts), do: :unknown

  defp require_supported_strategy(:tertian), do: :ok
  defp require_supported_strategy(_), do: :unsupported

  defp fetch_integer(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) -> {:ok, rem(value + 120, 12)}
      _ -> :error
    end
  end

  defp fetch_integer_list(map, key) do
    case Map.get(map, key) do
      values when is_list(values) and values != [] ->
        if Enum.all?(values, &is_integer/1) do
          {:ok, Enum.map(values, &rem(&1 + 120, 12))}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp resolve_quality(root_pc, chord_pcs, shape) do
    normalized_target = normalized_relative_intervals(root_pc, chord_pcs)

    matches =
      ChordSpec.qualities()
      |> Enum.filter(fn quality ->
        quality
        |> ChordSpec.quality_tones()
        |> Enum.map(&ChordSpec.tone_interval/1)
        |> Enum.map(&rem(&1 + 120, 12))
        |> Enum.uniq()
        |> Enum.sort() == normalized_target
      end)

    case matches do
      [quality] -> {:ok, quality}
      [] -> resolve_best_fit_quality(root_pc, chord_pcs, shape)
      many -> resolve_exact_ambiguity(many, shape)
    end
  end

  defp resolve_exact_ambiguity(matches, shape) when is_list(matches) do
    preferred =
      matches
      |> Enum.filter(&quality_matches_shape?(&1, shape))

    case preferred do
      [quality] -> {:ok, quality}
      _ -> :unknown
    end
  end

  defp resolve_best_fit_quality(root_pc, chord_pcs, shape)
       when shape in [:eleventh, :thirteenth, :add6, :six_nine] do
    target = normalized_relative_intervals(root_pc, chord_pcs)
    observed_size = length(target)

    shape_candidate_qualities(shape)
    |> Enum.map(fn quality ->
      expected =
        quality
        |> ChordSpec.quality_tones()
        |> Enum.map(&ChordSpec.tone_interval/1)
        |> Enum.map(&rem(&1 + 120, 12))
        |> Enum.uniq()
        |> Enum.sort()

      intersection = intersection_size(target, expected)
      missing = max(length(expected) - intersection, 0)
      extra = max(observed_size - intersection, 0)

      # Keep deterministic and root-preserving: choose best interval fit under the intended shape.
      score = intersection * 100 - missing * 35 - extra * 20
      {quality, score, intersection, missing, extra}
    end)
    |> Enum.sort_by(fn {quality, score, intersection, missing, extra} ->
      {-score, -intersection, missing, extra, quality_sort_key(quality)}
    end)
    |> case do
      [{quality, score, intersection, _, _} | _rest] ->
        min_intersection = min_intersection_for_shape(shape)

        if score > 0 and intersection >= min_intersection do
          {:ok, quality}
        else
          :unknown
        end

      _ ->
        :unknown
    end
  end

  defp resolve_best_fit_quality(_root_pc, _chord_pcs, _shape), do: :unknown

  defp shape_candidate_qualities(:eleventh), do: [:maj11, :min11, :dom11, :dom13, :min7_add11]

  defp shape_candidate_qualities(:thirteenth), do: [:maj13, :min13, :dom13]

  defp shape_candidate_qualities(:add6),
    do: [:maj6, :min6, :maj7_sharp5, :min_maj7, :dom7, :half_dim]

  defp shape_candidate_qualities(:six_nine), do: [:six_nine]

  defp min_intersection_for_shape(:eleventh), do: 4
  defp min_intersection_for_shape(:thirteenth), do: 5
  defp min_intersection_for_shape(:add6), do: 3
  defp min_intersection_for_shape(:six_nine), do: 3

  defp intersection_size(left, right) when is_list(left) and is_list(right) do
    left
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(right))
    |> MapSet.size()
  end

  defp quality_matches_shape?(quality, :triad),
    do: quality in [:maj, :min, :dim, :aug, :sus2, :sus4]

  defp quality_matches_shape?(quality, :seventh),
    do: quality in [:maj7, :min7, :dom7, :half_dim, :dim7, :min_maj7, :maj7_sharp5]

  defp quality_matches_shape?(quality, :ninth),
    do:
      quality in [
        :maj9,
        :min9,
        :min7_flat9,
        :dom9,
        :maj7_add_sharp9,
        :dim7_flat9,
        :min_maj9,
        :half_dim_flat9,
        :maj7_sharp5_9,
        :dom7_flat9
      ]

  defp quality_matches_shape?(quality, :eleventh),
    do: quality in [:maj11, :min11, :dom11, :min7_add11]

  defp quality_matches_shape?(quality, :thirteenth), do: quality in [:maj13, :min13, :dom13]
  defp quality_matches_shape?(quality, :add6), do: quality in [:maj6, :min6]
  defp quality_matches_shape?(quality, :six_nine), do: quality in [:six_nine]
  defp quality_matches_shape?(_quality, _shape), do: false

  defp quality_sort_key(quality) when is_atom(quality) do
    ChordSpec.qualities()
    |> Enum.find_index(&(&1 == quality))
    |> case do
      nil -> 999
      idx -> idx
    end
  end

  defp normalized_relative_intervals(root_pc, chord_pcs) do
    chord_pcs
    |> Enum.map(&rem(&1 - root_pc + 12, 12))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp resolve_spelled_root(
         %ScaleSpec{tonic: tonic, intervals: intervals} = scale_spec,
         root_pc,
         spelling_mode
       )
       when is_integer(root_pc) and spelling_mode in [:practical, :strict] do
    tonic_pc = ChordSpec.pitch_class_to_semitone(tonic)

    spelling_map =
      case ScaleGenerator.notes(scale_spec, spelling_mode) do
        {:ok, note_names} ->
          note_names
          |> Enum.zip(intervals)
          |> Enum.reduce(%{}, fn {note_name, interval}, acc ->
            semitone = rem(tonic_pc + interval, 12)

            case note_name_to_pitch_class_atom(note_name) do
              {:ok, atom} -> Map.put_new(acc, semitone, atom)
              :error -> acc
            end
          end)

        _ ->
          %{}
      end

    case Map.get(spelling_map, root_pc) do
      atom when is_atom(atom) and not is_nil(atom) -> {:ok, atom}
      _ -> {:ok, semitone_to_pitch_class(root_pc)}
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

  defp note_name_to_pitch_class_atom(_), do: :error

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
