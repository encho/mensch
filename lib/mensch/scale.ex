defmodule Mensch.Scale do
  @moduledoc """
  Public API for independent scale engine operations.
  """

  alias Mensch.Harmony.ChordSpec
  alias Mensch.Scale.ChordGenerator
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

  @spec chord_strategy_options() :: [map()]
  defdelegate chord_strategy_options(), to: ChordGenerator, as: :strategy_options

  @spec chord_shapes(atom()) :: {:ok, [atom()]} | {:error, term()}
  defdelegate chord_shapes(strategy_id), to: ChordGenerator, as: :strategy_shapes

  @spec generate_chord(ScaleSpec.t(), pos_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate generate_chord(scale_spec, degree, opts), to: ChordGenerator, as: :generate

  @doc """
  Builds explicit context labels for scale exports and diagnostics.

  Returns a map with:
  - `:scale` -> modal-tonic label (for example, "Eb Lydian #2 (Harmonic Minor Mode 6)")
  - `:parent_scale` -> parent family label when mode metadata is available

  Options:
  - `:spelling_mode` -> `:practical` (default) or `:strict`
  """
  @spec context_labels(ScaleSpec.t()) :: %{scale: String.t(), parent_scale: String.t() | nil}
  def context_labels(%ScaleSpec{} = scale_spec) do
    context_labels(scale_spec, [])
  end

  @spec context_labels(ScaleSpec.t(), keyword()) :: %{
          scale: String.t(),
          parent_scale: String.t() | nil
        }
  def context_labels(%ScaleSpec{} = scale_spec, opts) when is_list(opts) do
    spelling_mode = Keyword.get(opts, :spelling_mode, :practical)
    tonic_label = ChordSpec.root_label(scale_spec.tonic)
    family_name = family_name(scale_spec.family)

    scale_label =
      if is_integer(scale_spec.mode) do
        "#{tonic_label} #{scale_spec.name} (#{family_name} Mode #{scale_spec.mode})"
      else
        "#{tonic_label} #{family_name}"
      end

    %{
      scale: scale_label,
      parent_scale: parent_scale_label(scale_spec, spelling_mode)
    }
  end

  defp family_name(family) when is_atom(family) do
    case ScaleRegistry.fetch(family) do
      {:ok, %{name: name}} when is_binary(name) -> name
      _ -> family |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp parent_scale_label(
         %ScaleSpec{family: family, mode: mode, tonic: tonic} = scale_spec,
         spelling_mode
       )
       when is_atom(family) and is_integer(mode) and is_atom(tonic) and mode > 0 and
              spelling_mode in [:practical, :strict] do
    with {:ok, %{name: resolved_family_name, intervals: intervals}} <- ScaleRegistry.fetch(family),
         true <- is_list(intervals),
         true <- mode <= length(intervals),
         tonic_pc when is_integer(tonic_pc) <- ChordSpec.pitch_class_to_semitone(tonic),
         mode_offset when is_integer(mode_offset) <- Enum.at(intervals, mode - 1),
         {:ok, modal_notes} <- ScaleGenerator.notes(scale_spec, spelling_mode) do
      parent_pc = rem(tonic_pc - mode_offset + 120, 12)

      case select_parent_tonic(parent_pc, family, mode, modal_notes, spelling_mode) do
        {:ok, parent_tonic} ->
          "#{ChordSpec.root_label(parent_tonic)} #{resolved_family_name}"

        :error ->
          nil
      end
    else
      _ -> nil
    end
  end

  defp parent_scale_label(_scale_spec, _spelling_mode), do: nil

  defp select_parent_tonic(parent_pc, family, mode, modal_notes, spelling_mode)
       when is_integer(parent_pc) and is_atom(family) and is_integer(mode) and
              is_list(modal_notes) and
              spelling_mode in [:practical, :strict] do
    candidates = semitone_candidates(parent_pc)
    bias = accidental_bias(modal_notes)

    best =
      candidates
      |> Enum.map(fn candidate ->
        case build_parent_candidate(candidate, family, mode, modal_notes, spelling_mode, bias) do
          {:ok, scored} -> scored
          :error -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn scored ->
        {
          scored.mismatch_count,
          scored.readability_penalty,
          scored.bias_penalty,
          scored.candidate_rank
        }
      end)
      |> List.first()

    case best do
      %{tonic: tonic} -> {:ok, tonic}
      _ -> :error
    end
  end

  defp build_parent_candidate(candidate, family, mode, modal_notes, spelling_mode, bias) do
    with {:ok, parent_spec} <- build_scale(candidate, family, 1),
         {:ok, parent_notes} <- ScaleGenerator.notes(parent_spec, spelling_mode) do
      rotated = rotate_notes(parent_notes, mode)

      mismatch_count =
        Enum.zip(rotated, modal_notes)
        |> Enum.count(fn {left, right} -> left != right end)

      {:ok,
       %{
         tonic: candidate,
         mismatch_count: mismatch_count,
         readability_penalty: readability_penalty(parent_notes, spelling_mode),
         bias_penalty: bias_penalty(candidate, bias),
         candidate_rank: candidate_rank(candidate)
       }}
    else
      _ -> :error
    end
  end

  defp rotate_notes(notes, mode) when is_list(notes) and is_integer(mode) and mode > 0 do
    size = length(notes)

    if size == 0 do
      []
    else
      offset = rem(mode - 1, size)
      Enum.drop(notes, offset) ++ Enum.take(notes, offset)
    end
  end

  defp readability_penalty(notes, spelling_mode) do
    Enum.reduce(notes, 0, fn note, acc ->
      accidental_count = String.graphemes(note) |> Enum.count(&(&1 in ["#", "b"]))

      double_penalty =
        if String.contains?(note, "##") or String.contains?(note, "bb"), do: 4, else: 0

      case spelling_mode do
        :practical -> acc + accidental_count + double_penalty
        :strict -> acc + accidental_count
      end
    end)
  end

  defp accidental_bias(notes) when is_list(notes) do
    {sharp_count, flat_count} =
      Enum.reduce(notes, {0, 0}, fn note, {s_acc, f_acc} ->
        graphemes = String.graphemes(note)
        sharp_in_note = Enum.count(graphemes, &(&1 == "#"))
        flat_in_note = Enum.count(graphemes, &(&1 == "b"))

        {
          s_acc + sharp_in_note,
          f_acc + flat_in_note
        }
      end)

    cond do
      flat_count > sharp_count -> :flat
      sharp_count > flat_count -> :sharp
      true -> :neutral
    end
  end

  defp bias_penalty(candidate, :flat) do
    if flat_name?(candidate), do: 0, else: 1
  end

  defp bias_penalty(candidate, :sharp) do
    if sharp_name?(candidate), do: 0, else: 1
  end

  defp bias_penalty(_candidate, :neutral), do: 0

  defp candidate_rank(candidate) when is_atom(candidate) do
    cond do
      flat_name?(candidate) -> 0
      sharp_name?(candidate) -> 1
      true -> 2
    end
  end

  defp flat_name?(candidate) when is_atom(candidate),
    do: candidate |> Atom.to_string() |> String.contains?("flat")

  defp sharp_name?(candidate) when is_atom(candidate),
    do: candidate |> Atom.to_string() |> String.contains?("sharp")

  defp semitone_candidates(0), do: [:c]
  defp semitone_candidates(1), do: [:d_flat, :c_sharp]
  defp semitone_candidates(2), do: [:d]
  defp semitone_candidates(3), do: [:e_flat, :d_sharp]
  defp semitone_candidates(4), do: [:e]
  defp semitone_candidates(5), do: [:f]
  defp semitone_candidates(6), do: [:g_flat, :f_sharp]
  defp semitone_candidates(7), do: [:g]
  defp semitone_candidates(8), do: [:a_flat, :g_sharp]
  defp semitone_candidates(9), do: [:a]
  defp semitone_candidates(10), do: [:b_flat, :a_sharp]
  defp semitone_candidates(11), do: [:c_flat, :b]
end
