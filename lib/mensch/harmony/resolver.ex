defmodule Mensch.Harmony.Resolver do
  @moduledoc """
  Deterministic note resolver for `Mensch.Harmony.ChordSpec`.

  Pipeline:

      chord spec
      -> resolve chord tones
      -> apply inversion
      -> apply voicing
      -> add optional foreign bass
      -> final MIDI notes

  Design invariants:

  * Harmonic identity stays unchanged unless explicit doubling is requested.
  * Inversion is applied before voicing.
  * Foreign bass is independent and appended after voicing.
  * On invalid or unsatisfiable constraints, resolution fails hard.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.ChordSpec.ForeignBass
  alias Mensch.Harmony.ChordSpec.Voicing

  defmodule NoteDetail do
    @moduledoc "Harmonic metadata for a resolved note."

    defstruct [
      :midi_note,
      :named_note_name,
      :named_note_note,
      :named_note_octave,
      :note_distance,
      :degree_simple,
      :degree_compound_preferred,
      :interval_human_label,
      :chord_tone_role
    ]

    @type t :: %__MODULE__{
            midi_note: integer(),
            named_note_name: String.t(),
            named_note_note: String.t(),
            named_note_octave: integer(),
            note_distance: integer(),
            degree_simple: String.t(),
            degree_compound_preferred: String.t(),
            interval_human_label: String.t(),
            chord_tone_role: String.t()
          }
  end

  @type resolution_steps :: %{
          resolved_chord_tones: [integer()],
          inverted_chord_tones: [integer()],
          voiced_chord_tones: [integer()],
          foreign_bass_note: integer() | nil,
          final_notes: [integer()],
          final_note_details: [NoteDetail.t()]
        }

  @type inversion_sequence_entry :: %{
          inversion: integer(),
          final_notes: [integer()],
          voiced_chord_tones: [integer()]
        }

  @doc "Resolves a harmony chord spec to final MIDI notes."
  @spec resolve(ChordSpec.t()) :: [integer()]
  def resolve(%ChordSpec{} = spec) do
    spec
    |> resolve_steps()
    |> Map.fetch!(:final_notes)
  end

  @doc "Resolves a harmony chord spec and exposes all intermediate steps."
  @spec resolve_steps(ChordSpec.t()) :: resolution_steps()
  def resolve_steps(%ChordSpec{} = spec) do
    case ChordSpec.validate(spec) do
      :ok ->
        do_resolve_steps(spec)

      {:error, reason} ->
        raise ArgumentError, "invalid harmony chord spec: #{inspect(reason)}"
    end
  end

  @doc "Builds inversion sequence entries from inversion 0 to the requested inversion."
  @spec resolve_inversion_sequence(ChordSpec.t()) :: [inversion_sequence_entry()]
  def resolve_inversion_sequence(%ChordSpec{} = spec) do
    sequence_inversions(spec.inversion)
    |> Enum.map(fn inversion ->
      step_spec = %{spec | inversion: inversion}
      steps = resolve_steps(step_spec)

      %{
        inversion: inversion,
        final_notes: steps.final_notes,
        voiced_chord_tones: steps.voiced_chord_tones
      }
    end)
  end

  defp do_resolve_steps(%ChordSpec{} = spec) do
    case spec.voicing.inversion_resolution_mode do
      :per_step_centered ->
        do_resolve_steps_per_step_centered(spec)

      :anchor_then_wander ->
        do_resolve_steps_anchor_then_wander(spec)
    end
  end

  defp do_resolve_steps_per_step_centered(%ChordSpec{} = spec) do
    resolved_chord_tones = resolve_chord_tones(spec)
    inverted_chord_tones = apply_inversion(resolved_chord_tones, spec.inversion)
    voiced_chord_tones = apply_voicing(inverted_chord_tones, spec)

    foreign_bass_note =
      resolve_foreign_bass(spec, voiced_chord_tones, resolved_chord_tones)

    final_notes =
      voiced_chord_tones
      |> maybe_prepend_foreign_bass(foreign_bass_note)

    final_note_details =
      build_final_note_details(spec, final_notes, foreign_bass_note)

    %{
      resolved_chord_tones: resolved_chord_tones,
      inverted_chord_tones: inverted_chord_tones,
      voiced_chord_tones: voiced_chord_tones,
      foreign_bass_note: foreign_bass_note,
      final_notes: final_notes,
      final_note_details: final_note_details
    }
  end

  defp do_resolve_steps_anchor_then_wander(%ChordSpec{} = spec) do
    resolved_chord_tones = resolve_chord_tones(spec)
    inverted_chord_tones = apply_inversion(resolved_chord_tones, spec.inversion)

    anchor_voiced =
      resolved_chord_tones
      |> apply_inversion(0)
      |> apply_voicing(%{spec | inversion: 0})

    voiced_chord_tones =
      anchor_voiced
      |> wander_from_anchor(spec.inversion)

    if not valid_in_range?(voiced_chord_tones, spec.voicing) do
      raise ArgumentError,
            "anchor_then_wander voicing drift violates range constraints #{inspect({spec.voicing.range_min, spec.voicing.range_max})}"
    end

    ensure_all_notes_in_midi_range!(voiced_chord_tones)

    foreign_bass_note =
      resolve_foreign_bass(spec, voiced_chord_tones, resolved_chord_tones)

    final_notes =
      voiced_chord_tones
      |> maybe_prepend_foreign_bass(foreign_bass_note)

    final_note_details =
      build_final_note_details(spec, final_notes, foreign_bass_note)

    %{
      resolved_chord_tones: resolved_chord_tones,
      inverted_chord_tones: inverted_chord_tones,
      voiced_chord_tones: voiced_chord_tones,
      foreign_bass_note: foreign_bass_note,
      final_notes: final_notes,
      final_note_details: final_note_details
    }
  end

  defp build_final_note_details(%ChordSpec{} = spec, final_notes, foreign_bass_note) do
    root_pc = ChordSpec.pitch_class_to_semitone(spec.root)

    preferred_tokens_by_pc =
      spec
      |> ChordSpec.tones()
      |> Enum.uniq()
      |> Enum.reduce(%{}, fn token, acc ->
        pc = rem(ChordSpec.tone_interval(token), 12)
        Map.put_new(acc, pc, token)
      end)

    Enum.map(final_notes, fn midi_note ->
      note_pc = rem(midi_note, 12)
      note_distance = normalize_pc(note_pc - root_pc)
      degree_simple = degree_simple_for_distance(note_distance)

      token = Map.get(preferred_tokens_by_pc, note_pc)

      degree_compound_preferred =
        case token do
          nil -> degree_simple
          t -> degree_compound_from_token_or_simple(t, degree_simple)
        end

      {named_note_note, named_note_octave} =
        cond do
          is_integer(foreign_bass_note) and midi_note == foreign_bass_note and
              match?(%ForeignBass{}, spec.foreign_bass) ->
            spell_from_pitch_class_atom(spec.foreign_bass.pitch_class, midi_note)

          is_binary(token) ->
            spell_from_root_and_token(spec.root, token, midi_note)

          true ->
            spell_from_midi_fallback(midi_note)
        end

      %NoteDetail{
        midi_note: midi_note,
        named_note_name: "#{named_note_note}#{named_note_octave}",
        named_note_note: named_note_note,
        named_note_octave: named_note_octave,
        note_distance: note_distance,
        degree_simple: degree_simple,
        degree_compound_preferred: degree_compound_preferred,
        interval_human_label: interval_human_label(note_distance),
        chord_tone_role: chord_tone_role(token, midi_note, foreign_bass_note)
      }
    end)
  end

  defp chord_tone_role(_token, midi_note, foreign_bass_note)
       when is_integer(foreign_bass_note) and midi_note == foreign_bass_note,
       do: "foreign_bass"

  defp chord_tone_role("1", _midi_note, _foreign_bass_note), do: "root"

  defp chord_tone_role(token, _midi_note, _foreign_bass_note) when is_binary(token) do
    cond do
      token in ["b9", "#9", "#11", "b13", "b5", "#5"] -> "alteration"
      token_has_compound_degree?(token) -> "extension"
      true -> "chord_tone"
    end
  end

  defp chord_tone_role(_token, _midi_note, _foreign_bass_note), do: "non_chord_tone"

  defp degree_compound_from_token_or_simple(token, simple) do
    if token_has_compound_degree?(token), do: token, else: simple
  end

  defp token_has_compound_degree?(token) do
    case parse_tone_token(token) do
      {_acc, degree_num} -> degree_num in [9, 11, 13]
      :error -> false
    end
  end

  defp degree_simple_for_distance(distance) do
    case distance do
      0 -> "1"
      1 -> "b2"
      2 -> "2"
      3 -> "b3"
      4 -> "3"
      5 -> "4"
      6 -> "b5"
      7 -> "5"
      8 -> "b6"
      9 -> "6"
      10 -> "b7"
      11 -> "7"
    end
  end

  defp interval_human_label(distance) do
    case distance do
      0 -> "Perfect unison"
      1 -> "Minor second"
      2 -> "Major second"
      3 -> "Minor third"
      4 -> "Major third"
      5 -> "Perfect fourth"
      6 -> "Tritone"
      7 -> "Perfect fifth"
      8 -> "Minor sixth"
      9 -> "Major sixth"
      10 -> "Minor seventh"
      11 -> "Major seventh"
    end
  end

  defp spell_from_root_and_token(root_pitch_class, token, midi_note) do
    with {root_letter, root_acc} <- pitch_class_spelling!(root_pitch_class),
         {_token_acc, token_degree} <- parse_tone_token(token) do
      root_idx = letter_index(root_letter)
      root_pc = normalize_pc(letter_pc(root_letter) + root_acc)
      target_simple_degree = rem(token_degree - 1, 7) + 1

      target_letter =
        Enum.at(["C", "D", "E", "F", "G", "A", "B"], rem(root_idx + target_simple_degree - 1, 7))

      target_natural_pc = letter_pc(target_letter)
      desired_pc = normalize_pc(ChordSpec.tone_interval(token))
      base_interval = normalize_pc(target_natural_pc - root_pc)
      target_acc = accidental_for_interval(base_interval, desired_pc)
      octave = div(midi_note - target_natural_pc - target_acc, 12) - 1
      {target_letter <> accidental_text(target_acc), octave}
    else
      _ -> spell_from_midi_fallback(midi_note)
    end
  end

  defp spell_from_pitch_class_atom(pitch_class, midi_note) do
    {letter, acc} = pitch_class_spelling!(pitch_class)
    octave = div(midi_note - letter_pc(letter) - acc, 12) - 1
    {letter <> accidental_text(acc), octave}
  end

  defp spell_from_midi_fallback(midi_note) do
    note =
      case rem(midi_note, 12) do
        0 -> "C"
        1 -> "C#"
        2 -> "D"
        3 -> "D#"
        4 -> "E"
        5 -> "F"
        6 -> "F#"
        7 -> "G"
        8 -> "G#"
        9 -> "A"
        10 -> "A#"
        11 -> "B"
      end

    {note, div(midi_note, 12) - 1}
  end

  defp pitch_class_spelling!(pitch_class) do
    case pitch_class do
      :c -> {"C", 0}
      :c_flat -> {"C", -1}
      :b_sharp -> {"B", 1}
      :c_sharp -> {"C", 1}
      :d_flat -> {"D", -1}
      :d -> {"D", 0}
      :d_sharp -> {"D", 1}
      :e_flat -> {"E", -1}
      :e -> {"E", 0}
      :f_flat -> {"F", -1}
      :e_sharp -> {"E", 1}
      :f -> {"F", 0}
      :f_sharp -> {"F", 1}
      :g_flat -> {"G", -1}
      :g -> {"G", 0}
      :g_sharp -> {"G", 1}
      :a_flat -> {"A", -1}
      :a -> {"A", 0}
      :a_sharp -> {"A", 1}
      :b_flat -> {"B", -1}
      :b -> {"B", 0}
    end
  end

  defp parse_tone_token(token) when is_binary(token) do
    case Regex.run(~r/^(bb|b|#)?(\d+)$/, token, capture: :all_but_first) do
      [accidental, degree_num] -> {accidental_value(accidental), String.to_integer(degree_num)}
      [degree_num] -> {0, String.to_integer(degree_num)}
      _ -> :error
    end
  end

  defp accidental_value("bb"), do: -2
  defp accidental_value("b"), do: -1
  defp accidental_value("#"), do: 1
  defp accidental_value(_), do: 0

  defp accidental_text(acc) when acc > 0, do: String.duplicate("#", acc)
  defp accidental_text(acc) when acc < 0, do: String.duplicate("b", abs(acc))
  defp accidental_text(_acc), do: ""

  defp letter_pc("C"), do: 0
  defp letter_pc("D"), do: 2
  defp letter_pc("E"), do: 4
  defp letter_pc("F"), do: 5
  defp letter_pc("G"), do: 7
  defp letter_pc("A"), do: 9
  defp letter_pc("B"), do: 11

  defp letter_index("C"), do: 0
  defp letter_index("D"), do: 1
  defp letter_index("E"), do: 2
  defp letter_index("F"), do: 3
  defp letter_index("G"), do: 4
  defp letter_index("A"), do: 5
  defp letter_index("B"), do: 6

  defp normalize_pc(value), do: rem(value + 120, 12)

  defp accidental_for_interval(base_interval, desired_pc) do
    case Enum.find(-2..2, fn accidental ->
           normalize_pc(base_interval + accidental) == desired_pc
         end) do
      nil ->
        0

      accidental ->
        accidental
    end
  end

  defp resolve_chord_tones(%ChordSpec{} = spec) do
    root_midi = ChordSpec.midi_note_number(spec.root, spec.octave)

    spec
    |> ChordSpec.tone_intervals()
    |> Enum.map(&(&1 + root_midi))
    |> Enum.sort()
  end

  defp apply_inversion(notes, inversion) when inversion > 0 do
    1..inversion
    |> Enum.reduce(Enum.sort(notes), fn _, acc ->
      [lowest | rest] = acc
      Enum.sort(rest ++ [lowest + 12])
    end)
  end

  defp apply_inversion(notes, inversion) when inversion < 0 do
    1..abs(inversion)
    |> Enum.reduce(Enum.sort(notes), fn _, acc ->
      highest = List.last(acc)
      front = Enum.drop(acc, -1)
      Enum.sort([highest - 12 | front])
    end)
  end

  defp apply_inversion(notes, _inversion), do: Enum.sort(notes)

  defp apply_voicing(inverted_notes, %ChordSpec{voicing: %Voicing{} = voicing} = spec) do
    notes =
      inverted_notes
      |> normalize_voice_count(spec, voicing)
      |> maybe_apply_open_voicing(voicing.type)
      |> Enum.sort()
      |> align_to_center_and_range(voicing)

    ensure_all_notes_in_midi_range!(notes)
    notes
  end

  defp normalize_voice_count(inverted_notes, %ChordSpec{} = spec, %Voicing{} = voicing) do
    source_count = length(inverted_notes)
    target_count = voicing.voice_count || source_count

    cond do
      target_count == source_count ->
        inverted_notes

      target_count < source_count ->
        raise ArgumentError,
              "unsatisfiable voice_count #{target_count}: cannot be lower than source chord tone count #{source_count}"

      true ->
        add_doubled_voices(inverted_notes, spec, target_count, voicing.doubling)
    end
  end

  defp add_doubled_voices(notes, spec, target_count, doubling) do
    additional = target_count - length(notes)

    additions =
      case doubling do
        :root ->
          root_pc = ChordSpec.pitch_class_to_semitone(spec.root)
          build_additions_by_pitch_class(notes, [root_pc], additional)

        :top ->
          build_top_additions(notes, additional)

        :auto ->
          order = auto_doubling_order(spec)
          build_additions_by_pitch_class(notes, order, additional)

        :third ->
          order = pitch_classes_for_tokens(spec, ["3", "b3"])

          if order == [] do
            raise ArgumentError,
                  "doubling mode :third requires a chord quality with a third"
          end

          build_additions_by_pitch_class(notes, order, additional)

        :fifth ->
          order = pitch_classes_for_tokens(spec, ["5", "b5", "#5"])

          if order == [] do
            raise ArgumentError,
                  "doubling mode :fifth requires a chord quality with a fifth-family tone"
          end

          build_additions_by_pitch_class(notes, order, additional)

        :guide_tones ->
          order = pitch_classes_for_tokens(spec, ["3", "b3", "7", "b7", "bb7"])

          if order == [] do
            raise ArgumentError,
                  "doubling mode :guide_tones requires at least one guide tone (third or seventh)"
          end

          build_additions_by_pitch_class(notes, order, additional)

        :bass ->
          bass_pc = rem(Enum.min(notes), 12)
          build_additions_by_pitch_class(notes, [bass_pc], additional)
      end

    Enum.sort(notes ++ additions)
  end

  # Auto doubling priority: root, fifth, third, then seventh/tensions.
  defp auto_doubling_order(%ChordSpec{} = spec) do
    intervals = ChordSpec.tone_intervals(spec)

    [0, 7, 3, 4] ++
      (intervals
       |> Enum.map(&rem(&1, 12))
       |> Enum.reject(&(&1 in [0, 7, 3, 4]))
       |> Enum.uniq())
  end

  defp pitch_classes_for_tokens(%ChordSpec{} = spec, ordered_tokens) do
    available_tokens = MapSet.new(ChordSpec.tones(spec))

    ordered_tokens
    |> Enum.filter(&MapSet.member?(available_tokens, &1))
    |> Enum.map(fn token ->
      token
      |> ChordSpec.tone_interval()
      |> rem(12)
    end)
    |> Enum.uniq()
  end

  defp build_additions_by_pitch_class(notes, pcs_order, additional_count) do
    existing_counts =
      Enum.reduce(notes, %{}, fn note, acc -> Map.update(acc, rem(note, 12), 1, &(&1 + 1)) end)

    highest_by_pc =
      Enum.reduce(notes, %{}, fn note, acc ->
        Map.update(acc, rem(note, 12), note, &max(&1, note))
      end)

    1..additional_count
    |> Enum.reduce({[], existing_counts, highest_by_pc}, fn step, {acc, counts, highs} ->
      pc = Enum.at(pcs_order, rem(step - 1, max(length(pcs_order), 1)))

      case pc do
        nil ->
          raise ArgumentError, "cannot build doubled voices: no doubling pitch classes available"

        _ ->
          current_high = Map.get(highs, pc, Enum.max(notes))

          next_note =
            if rem(current_high, 12) == pc,
              do: current_high + 12,
              else: closest_at_or_above(pc, current_high + 1)

          {
            [next_note | acc],
            Map.update(counts, pc, 1, &(&1 + 1)),
            Map.put(highs, pc, next_note)
          }
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp build_top_additions(notes, additional_count) do
    top = Enum.max(notes)

    1..additional_count
    |> Enum.map(fn idx -> top + idx * 12 end)
  end

  # Open voicing v1 rule:
  # keep the lowest voice, raise every 2nd upper voice (2nd, 4th, ...) by one octave.
  defp maybe_apply_open_voicing(notes, :close), do: notes

  defp maybe_apply_open_voicing([lowest | uppers], :open) do
    transformed_uppers =
      uppers
      |> Enum.with_index(1)
      |> Enum.map(fn {note, upper_index} ->
        if rem(upper_index, 2) == 0 do
          note + 12
        else
          note
        end
      end)

    Enum.sort([lowest | transformed_uppers])
  end

  defp maybe_apply_open_voicing([], :open), do: []

  defp align_to_center_and_range(notes, %Voicing{} = voicing) do
    candidates =
      for shift <- -10..10 do
        shifted = Enum.map(notes, &(&1 + shift * 12))

        if valid_in_range?(shifted, voicing) do
          {shifted, objective_distance(shifted, voicing.center_note), abs(shift), shift}
        else
          nil
        end
      end
      |> Enum.reject(&is_nil/1)

    case candidates do
      [] ->
        raise ArgumentError,
              "unsatisfiable voicing constraints for center_note #{voicing.center_note} and range #{inspect({voicing.range_min, voicing.range_max})}"

      _ ->
        {best, _distance, _abs_shift, _shift} =
          Enum.min_by(candidates, fn {_notes, dist, abs_shift, shift} ->
            {dist, abs_shift, shift}
          end)

        best
    end
  end

  defp objective_distance(notes, center_note) do
    median = Enum.at(notes, div(length(notes), 2))
    abs(median - center_note)
  end

  defp wander_from_anchor(anchor_voiced, 0), do: Enum.sort(anchor_voiced)

  defp wander_from_anchor(anchor_voiced, inversion) when inversion > 0 do
    1..inversion
    |> Enum.reduce(Enum.sort(anchor_voiced), fn _, notes ->
      [lowest | rest] = notes
      Enum.sort(rest ++ [lowest + 12])
    end)
  end

  defp wander_from_anchor(anchor_voiced, inversion) when inversion < 0 do
    1..abs(inversion)
    |> Enum.reduce(Enum.sort(anchor_voiced), fn _, notes ->
      highest = List.last(notes)
      front = Enum.drop(notes, -1)
      Enum.sort([highest - 12 | front])
    end)
  end

  defp sequence_inversions(target_inversion) when target_inversion >= 0,
    do: Enum.to_list(0..target_inversion)

  defp sequence_inversions(target_inversion) do
    0..abs(target_inversion)
    |> Enum.map(&(-&1))
  end

  defp valid_in_range?(notes, %Voicing{range_min: nil, range_max: nil}),
    do: Enum.all?(notes, &(&1 >= 0 and &1 <= 127))

  defp valid_in_range?(notes, %Voicing{range_min: min_note, range_max: max_note}) do
    Enum.all?(notes, fn n ->
      in_midi = n >= 0 and n <= 127
      above_min = is_nil(min_note) or n >= min_note
      below_max = is_nil(max_note) or n <= max_note
      in_midi and above_min and below_max
    end)
  end

  defp maybe_prepend_foreign_bass(notes, nil), do: notes

  defp maybe_prepend_foreign_bass(notes, bass_note) do
    [bass_note | notes]
    |> Enum.sort()
  end

  defp ensure_all_notes_in_midi_range!(notes) do
    case Enum.find(notes, &(&1 < 0 or &1 > 127)) do
      nil -> :ok
      out -> raise ArgumentError, "midi note out of range: #{out}"
    end
  end

  defp resolve_foreign_bass(%ChordSpec{foreign_bass: nil}, _voiced_notes, _resolved_notes),
    do: nil

  defp resolve_foreign_bass(
         %ChordSpec{foreign_bass: %ForeignBass{} = bass, voicing: voicing},
         voiced_notes,
         resolved_notes
       ) do
    chord_pitch_classes = resolved_notes |> Enum.map(&rem(&1, 12)) |> MapSet.new()
    bass_pc = ChordSpec.pitch_class_to_semitone(bass.pitch_class)

    if MapSet.member?(chord_pitch_classes, bass_pc) do
      raise ArgumentError,
            "foreign_bass #{inspect(bass.pitch_class)} is not foreign: pitch class belongs to chord tones"
    end

    bass_note =
      case bass.mode do
        :absolute ->
          ChordSpec.midi_note_number(bass.pitch_class, bass.octave)

        :relative ->
          place_foreign_bass_relative(voiced_notes, bass_pc, bass.octave)
      end

    if not valid_in_range?([bass_note], voicing) do
      raise ArgumentError,
            "foreign bass #{bass_note} violates voicing range constraints #{inspect({voicing.range_min, voicing.range_max})}"
    end

    if bass_note >= Enum.min(voiced_notes) do
      raise ArgumentError,
            "foreign bass #{bass_note} must be below the lowest voiced chord tone #{Enum.min(voiced_notes)}"
    end

    ensure_all_notes_in_midi_range!([bass_note])
    bass_note
  end

  defp place_foreign_bass_relative(voiced_notes, bass_pc, relative_octaves_below) do
    lowest = Enum.min(voiced_notes)
    lowest_octave = div(lowest, 12) - 1
    target_octave = lowest_octave - relative_octaves_below

    candidate =
      bass_pc
      |> semitone_to_pitch_class!()
      |> ChordSpec.midi_note_number(target_octave)
      |> ensure_strictly_below(lowest)

    if candidate < 0 do
      raise ArgumentError,
            "cannot place foreign bass pitch class #{bass_pc} below voiced chord without leaving MIDI range"
    end

    candidate
  end

  defp ensure_strictly_below(note, lowest) when note >= lowest, do: note - 12
  defp ensure_strictly_below(note, _lowest), do: note

  defp semitone_to_pitch_class!(semitone) do
    case rem(semitone, 12) do
      0 -> :c
      1 -> :c_sharp
      2 -> :d
      3 -> :d_sharp
      4 -> :e
      5 -> :f
      6 -> :f_sharp
      7 -> :g
      8 -> :g_sharp
      9 -> :a
      10 -> :a_sharp
      11 -> :b
    end
  end

  defp closest_at_or_above(pc, at_least) when is_integer(pc) and is_integer(at_least) do
    # MIDI note n has pitch class `rem(n, 12)`.
    base = at_least - rem(at_least, 12) + pc
    if base < at_least, do: base + 12, else: base
  end
end
