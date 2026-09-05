defmodule Mensch.Harmony.Resolver do
  @moduledoc """
  Resolves a `Mensch.Harmony.ChordSpec` against a `Mensch.Harmony.Key`
  into a `Mensch.Harmony.ResolvedChord`.

  The harmony layer describes music (note names), not performance
  (MIDI numbers, velocities, timing) — those belong to the machine and
  performance layers.
  """

  alias Mensch.Harmony.{ChordSpec, Key, ResolvedChord}

  @chord_tones %{
    min7: [0, 3, 7, 10],
    dom7: [0, 4, 7, 10],
    maj7: [0, 4, 7, 11]
  }

  @doc """
  Resolves `chord_spec` against `key` into a `ResolvedChord`.

      iex> Mensch.Harmony.Resolver.resolve(%Mensch.Harmony.Key{root: :c, scale: :major}, %Mensch.Harmony.ChordSpec{degree: :ii, modifier: :min7})
      %Mensch.Harmony.ResolvedChord{root: :d, notes: [:d, :f, :a, :c], degree: :ii, modifier: :min7}

  """
  @spec resolve(Key.t(), ChordSpec.t()) :: ResolvedChord.t()
  def resolve(%Key{} = key, %ChordSpec{degree: degree, modifier: modifier}) do
    root = Key.note_at_degree(key, degree)
    intervals = Map.fetch!(@chord_tones, modifier)
    notes = Enum.map(intervals, &Key.transpose(root, &1))

    %ResolvedChord{root: root, notes: notes, degree: degree, modifier: modifier}
  end
end
