defmodule Mensch.Scale.ScaleGenerator do
  @moduledoc """
  Converts `Mensch.Scale.ScaleSpec` into named notes and MIDI sets.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Scale.ScaleSpec

  @letters [:c, :d, :e, :f, :g, :a, :b]

  @base_pc %{
    c: 0,
    d: 2,
    e: 4,
    f: 5,
    g: 7,
    a: 9,
    b: 11
  }

  @token_by_accidental %{-2 => "bb", -1 => "b", 0 => "", 1 => "#", 2 => "##"}

  # Candidate diatonic degrees for each semitone offset.
  # Multiple candidates handle ambiguous spellings (e.g. #5 vs b6).
  @interval_degree_candidates %{
    0 => [1],
    1 => [2],
    2 => [2],
    3 => [3],
    4 => [3],
    5 => [4],
    6 => [4, 5],
    7 => [5],
    8 => [5, 6],
    9 => [6],
    10 => [7, 6],
    11 => [7]
  }

  @pitch_spelling %{
    c: {:c, 0},
    c_flat: {:c, -1},
    b_sharp: {:b, 1},
    c_sharp: {:c, 1},
    d_flat: {:d, -1},
    d: {:d, 0},
    d_sharp: {:d, 1},
    e_flat: {:e, -1},
    e: {:e, 0},
    f_flat: {:f, -1},
    e_sharp: {:e, 1},
    f: {:f, 0},
    f_sharp: {:f, 1},
    g_flat: {:g, -1},
    g: {:g, 0},
    g_sharp: {:g, 1},
    a_flat: {:a, -1},
    a: {:a, 0},
    a_sharp: {:a, 1},
    b_flat: {:b, -1},
    b: {:b, 0},
    d_double_flat: {:d, -2},
    d_double_sharp: {:d, 2},
    e_double_flat: {:e, -2},
    e_double_sharp: {:e, 2},
    f_double_flat: {:f, -2},
    f_double_sharp: {:f, 2},
    g_double_flat: {:g, -2},
    g_double_sharp: {:g, 2},
    a_double_flat: {:a, -2},
    a_double_sharp: {:a, 2},
    c_double_flat: {:c, -2},
    b_double_sharp: {:b, 2}
  }

  @spec notes(ScaleSpec.t()) :: {:ok, [String.t()]} | {:error, term()}
  def notes(%ScaleSpec{} = scale_spec) do
    notes(scale_spec, :practical)
  end

  @spec notes(ScaleSpec.t(), :practical | :strict) :: {:ok, [String.t()]} | {:error, term()}
  def notes(%ScaleSpec{} = scale_spec, spelling_mode)
      when spelling_mode in [:practical, :strict] do
    with {:ok, tonic_pc} <- tonic_pitch_class(scale_spec.tonic),
         {:ok, tonic_letter} <- tonic_spelling(scale_spec.tonic),
         :ok <- validate_intervals(scale_spec.intervals) do
      letter_index = letter_index(tonic_letter)

      degree_path =
        case spelling_mode do
          :strict ->
            {:ok, Enum.to_list(1..length(scale_spec.intervals))}

          :practical ->
            choose_degree_path(scale_spec.intervals, tonic_pc, tonic_letter, :practical)
        end

      case degree_path do
        {:ok, degrees} ->
          named_notes =
            degrees
            |> Enum.zip(scale_spec.intervals)
            |> Enum.map(fn {degree, interval} ->
              letter = Enum.at(@letters, rem(letter_index + degree - 1, 7))
              desired_pc = rem(tonic_pc + interval, 12)
              letter_pc = @base_pc[letter]
              accidental = accidental_delta(letter_pc, desired_pc)
              render_note(letter, accidental)
            end)

          {:ok, named_notes}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec pitch_classes(ScaleSpec.t()) :: {:ok, [integer()]} | {:error, term()}
  def pitch_classes(%ScaleSpec{} = scale_spec) do
    with {:ok, tonic_pc} <- tonic_pitch_class(scale_spec.tonic),
         :ok <- validate_intervals(scale_spec.intervals) do
      pcs =
        scale_spec.intervals
        |> Enum.map(&rem(tonic_pc + &1, 12))
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, pcs}
    end
  end

  @spec midi_notes(ScaleSpec.t(), integer(), integer()) :: {:ok, [integer()]} | {:error, term()}
  def midi_notes(%ScaleSpec{} = scale_spec, min_note, max_note)
      when is_integer(min_note) and is_integer(max_note) do
    with {:ok, tonic_pc} <- tonic_pitch_class(scale_spec.tonic),
         :ok <- validate_intervals(scale_spec.intervals),
         :ok <- validate_range(min_note, max_note) do
      set = MapSet.new(scale_spec.intervals)

      notes =
        min_note..max_note
        |> Enum.filter(fn midi_note ->
          rem(midi_note - tonic_pc + 120, 12) in set
        end)

      {:ok, notes}
    end
  end

  def midi_notes(_scale_spec, _min_note, _max_note), do: {:error, :invalid_range}

  @spec tonic_midi_notes(ScaleSpec.t(), integer(), integer()) ::
          {:ok, [integer()]} | {:error, term()}
  def tonic_midi_notes(%ScaleSpec{} = scale_spec, min_note, max_note)
      when is_integer(min_note) and is_integer(max_note) do
    with {:ok, tonic_pc} <- tonic_pitch_class(scale_spec.tonic),
         :ok <- validate_range(min_note, max_note) do
      notes =
        min_note..max_note
        |> Enum.filter(fn midi_note ->
          rem(midi_note, 12) == tonic_pc
        end)

      {:ok, notes}
    end
  end

  def tonic_midi_notes(_scale_spec, _min_note, _max_note), do: {:error, :invalid_range}

  @doc """
  Returns scale MIDI notes constrained to complete tonic-to-tonic octaves.

  The returned list starts at the first tonic within the requested range and
  ends at the last tonic in range. If fewer than two tonic notes exist in the
  range, returns an empty note set.
  """
  @spec midi_notes_full_octaves(ScaleSpec.t(), integer(), integer()) ::
          {:ok, [integer()]} | {:error, term()}
  def midi_notes_full_octaves(%ScaleSpec{} = scale_spec, min_note, max_note)
      when is_integer(min_note) and is_integer(max_note) do
    with {:ok, scale_notes} <- midi_notes(scale_spec, min_note, max_note),
         {:ok, tonic_notes} <- tonic_midi_notes(scale_spec, min_note, max_note) do
      case tonic_notes do
        [first_tonic | _rest] when length(tonic_notes) >= 2 ->
          last_tonic = List.last(tonic_notes)

          notes =
            scale_notes
            |> Enum.filter(&(&1 >= first_tonic and &1 <= last_tonic))
            |> Enum.sort()

          {:ok, notes}

        _ ->
          {:ok, []}
      end
    end
  end

  def midi_notes_full_octaves(_scale_spec, _min_note, _max_note), do: {:error, :invalid_range}

  defp tonic_pitch_class(tonic) when is_atom(tonic) do
    case ChordSpec.pitch_class_to_semitone(tonic) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, :invalid_tonic}
    end
  end

  defp tonic_pitch_class(_tonic), do: {:error, :invalid_tonic}

  defp tonic_spelling(tonic) when is_atom(tonic) do
    case Map.get(@pitch_spelling, tonic) do
      {letter, _accidental} -> {:ok, letter}
      nil -> {:error, :invalid_tonic_spelling}
    end
  end

  defp validate_intervals(intervals) when is_list(intervals) do
    normalized = intervals |> Enum.uniq() |> Enum.sort()

    cond do
      normalized == [] -> {:error, :empty_intervals}
      Enum.at(normalized, 0) != 0 -> {:error, :intervals_must_start_with_zero}
      Enum.any?(normalized, &(&1 < 0 or &1 > 11)) -> {:error, :intervals_out_of_range}
      true -> :ok
    end
  end

  defp validate_intervals(_), do: {:error, :invalid_intervals}

  defp validate_range(min_note, max_note) do
    cond do
      min_note < 0 -> {:error, :invalid_range}
      max_note > 127 -> {:error, :invalid_range}
      min_note > max_note -> {:error, :invalid_range}
      true -> :ok
    end
  end

  defp letter_index(letter), do: Enum.find_index(@letters, &(&1 == letter))

  defp choose_degree_path(intervals, tonic_pc, tonic_letter, spelling_mode) do
    state = %{best_cost: nil, best_path: nil}
    letter_index = letter_index(tonic_letter)

    result =
      intervals
      |> Enum.with_index()
      |> search_degree_paths(0, nil, [], 0, state, tonic_pc, letter_index, spelling_mode)

    case result.best_path do
      nil -> {:error, :unable_to_spell_scale}
      path -> {:ok, path}
    end
  end

  defp search_degree_paths(
         indexed_intervals,
         idx,
         last_degree,
         acc_path,
         acc_cost,
         state,
         tonic_pc,
         tonic_letter_idx,
         spelling_mode
       ) do
    if idx >= length(indexed_intervals) do
      maybe_store_best(state, acc_cost, Enum.reverse(acc_path))
    else
      {interval, _position} = Enum.at(indexed_intervals, idx)
      candidates = Map.get(@interval_degree_candidates, interval, [1])

      Enum.reduce(candidates, state, fn degree, st ->
        if valid_degree_progression?(last_degree, degree) do
          letter = Enum.at(@letters, rem(tonic_letter_idx + degree - 1, 7))
          desired_pc = rem(tonic_pc + interval, 12)
          letter_pc = @base_pc[letter]
          accidental = accidental_delta(letter_pc, desired_pc)

          repeat_penalty = if degree == last_degree, do: 3, else: 0
          double_penalty = if abs(accidental) > 1, do: 5, else: 0
          next_cost = acc_cost + abs(accidental) + repeat_penalty + double_penalty

          next_cost =
            case spelling_mode do
              :strict -> next_cost
              :practical -> next_cost
            end

          if is_nil(st.best_cost) or next_cost <= st.best_cost do
            search_degree_paths(
              indexed_intervals,
              idx + 1,
              degree,
              [degree | acc_path],
              next_cost,
              st,
              tonic_pc,
              tonic_letter_idx,
              spelling_mode
            )
          else
            st
          end
        else
          st
        end
      end)
    end
  end

  defp valid_degree_progression?(nil, _degree), do: true
  defp valid_degree_progression?(last_degree, degree), do: degree >= last_degree

  defp maybe_store_best(state, cost, path) do
    cond do
      is_nil(state.best_cost) -> %{state | best_cost: cost, best_path: path}
      cost < state.best_cost -> %{state | best_cost: cost, best_path: path}
      true -> state
    end
  end

  defp accidental_delta(from_pc, to_pc) do
    candidates = for a <- -2..2, rem(from_pc + a + 120, 12) == to_pc, do: a
    Enum.min_by(candidates, &abs/1, fn -> 0 end)
  end

  defp render_note(letter, accidental) do
    base = letter |> Atom.to_string() |> String.upcase()
    token = Map.get(@token_by_accidental, accidental, "")
    base <> token
  end
end
