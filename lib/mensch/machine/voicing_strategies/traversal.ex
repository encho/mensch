defmodule Mensch.Machine.VoicingStrategies.Traversal do
  @moduledoc """
  Voicing strategy for directional traversals across octave-expanded chord tones.

  `octave_min_offset` and `octave_max_offset` define octave expansion relative
  to the chord's base octave. `direction` controls traversal order and
  `cycle_count` repeats that traversal pattern.
  """

  @behaviour Mensch.Machine.VoicingStrategy

  alias Mensch.ChordSpec

  @type direction :: :up | :down | :ping_pong

  @type t :: %__MODULE__{
          direction: direction(),
          octave_min_offset: integer(),
          octave_max_offset: integer(),
          cycle_count: pos_integer()
        }

  @enforce_keys [:direction, :octave_min_offset, :octave_max_offset, :cycle_count]
  defstruct [:direction, :octave_min_offset, :octave_max_offset, :cycle_count]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    direction = Keyword.get(opts, :direction, :up)
    octave_min_offset = Keyword.get(opts, :octave_min_offset, 0)
    octave_max_offset = Keyword.get(opts, :octave_max_offset, 1)
    cycle_count = Keyword.get(opts, :cycle_count, 1)

    normalized_direction = normalize_direction(direction)
    normalized_min = min(octave_min_offset, octave_max_offset)
    normalized_max = max(octave_min_offset, octave_max_offset)

    %__MODULE__{
      direction: normalized_direction,
      octave_min_offset: normalized_min,
      octave_max_offset: normalized_max,
      cycle_count: max(cycle_count, 1)
    }
  end

  @impl true
  @spec build_voiced_notes(t(), ChordSpec.t()) :: [Mensch.Machine.VoicingStrategy.voiced_note()]
  def build_voiced_notes(%__MODULE__{} = strategy, %ChordSpec{} = chord_spec) do
    base_degrees =
      chord_spec
      |> ChordSpec.to_midi_notes()
      |> Enum.with_index()

    expanded =
      expand_octaves(base_degrees, strategy.octave_min_offset, strategy.octave_max_offset)

    expanded
    |> directional_pattern(strategy.direction)
    |> repeat_pattern(strategy.cycle_count)
    |> Enum.with_index()
    |> Enum.map(fn {{note_number, degree_index}, event_index} ->
      %{note: note_number, degree_index: degree_index, event_index: event_index}
    end)
  end

  defp expand_octaves(base_degrees, min_offset, max_offset) do
    for octave_offset <- min_offset..max_offset,
        {note_number, degree_index} <- base_degrees do
      {note_number + octave_offset * 12, degree_index}
    end
  end

  defp directional_pattern(expanded, :up), do: expanded
  defp directional_pattern(expanded, :down), do: Enum.reverse(expanded)

  defp directional_pattern([], :ping_pong), do: []

  defp directional_pattern(expanded, :ping_pong) do
    forward = expanded

    backward =
      expanded
      |> Enum.reverse()
      |> drop_turning_points()

    forward ++ backward
  end

  defp drop_turning_points([]), do: []
  defp drop_turning_points([_single]), do: []

  defp drop_turning_points(backward) do
    backward
    |> tl()
    |> Enum.drop(-1)
  end

  defp repeat_pattern(_pattern, 0), do: []
  defp repeat_pattern(pattern, 1), do: pattern

  defp repeat_pattern(pattern, cycle_count) when cycle_count > 1 do
    List.duplicate(pattern, cycle_count)
    |> List.flatten()
  end

  defp normalize_direction(:up), do: :up
  defp normalize_direction(:down), do: :down
  defp normalize_direction(:ping_pong), do: :ping_pong
  defp normalize_direction(_other), do: :up
end
