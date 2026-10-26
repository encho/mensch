defmodule Mensch.Harmony.Progression.Middleware.EnsureBassAscending do
  @moduledoc """
  Ensures a progression is bass-ascending (non-decreasing) by tweaking center_note.

  Uses the first chord as reference and for each successive chord selects the
  nearest candidate whose bass note is >= previous bass.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Resolver

  @type opts :: [include_foreign_bass: boolean()]

  @spec middleware(opts()) :: (list(ChordSpec.t()) ->
                                 {:ok, list(ChordSpec.t())} | {:error, term()})
  def middleware(opts \\ []) when is_list(opts) do
    include_foreign_bass = Keyword.get(opts, :include_foreign_bass, false)

    fn chord_list ->
      ensure_bass_ascending(chord_list, include_foreign_bass)
    end
  end

  defp ensure_bass_ascending([], _include_foreign_bass), do: {:ok, []}

  defp ensure_bass_ascending([first | rest], include_foreign_bass) do
    with {:ok, first_bass} <- resolve_bass(first, include_foreign_bass),
         {:ok, result} <- step(rest, [first], first_bass, include_foreign_bass) do
      {:ok, result}
    end
  end

  defp step([], acc, _previous_bass, _include_foreign_bass), do: {:ok, acc}

  defp step([current | tail], acc, previous_bass, include_foreign_bass) do
    with {:ok, candidate, bass} <-
           pick_nearest_non_decreasing(current, previous_bass, include_foreign_bass) do
      step(tail, acc ++ [candidate], bass, include_foreign_bass)
    end
  end

  defp pick_nearest_non_decreasing(chord_spec, previous_bass, include_foreign_bass) do
    base_center = chord_spec.voicing.center_note

    shifts = [0, 12, -12, 24, -24, 36, -36, 48, -48]

    candidates =
      shifts
      |> Enum.map(fn shift ->
        candidate = put_in(chord_spec.voicing.center_note, base_center + shift)

        case resolve_bass(candidate, include_foreign_bass) do
          {:ok, bass} -> {:ok, candidate, bass, shift}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Enum.filter(fn
        {:ok, _candidate, bass, _shift} -> bass >= previous_bass
        _ -> false
      end)

    case candidates do
      [] ->
        {:error, {:no_non_decreasing_bass_candidate, previous_bass}}

      _ ->
        {:ok, best_candidate, best_bass, _shift} =
          Enum.min_by(candidates, fn {:ok, _candidate, bass, shift} ->
            {bass - previous_bass, abs(shift)}
          end)

        {:ok, best_candidate, best_bass}
    end
  end

  defp resolve_bass(chord_spec, include_foreign_bass) do
    steps = Resolver.resolve_steps(chord_spec)

    notes =
      if include_foreign_bass do
        steps.final_notes
      else
        steps.voiced_chord_tones
      end

    case notes do
      [] -> {:error, :empty_resolved_notes}
      _ -> {:ok, Enum.min(notes)}
    end
  rescue
    error in [ArgumentError] ->
      {:error, {:resolve_failed, Exception.message(error)}}
  end
end
