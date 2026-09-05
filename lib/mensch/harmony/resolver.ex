defmodule Mensch.Harmony.Resolver do
  @moduledoc """
  Resolves a `Mensch.Harmony.ChordSpec` against a `Mensch.Harmony.Scale`
  into a `Mensch.Harmony.ResolvedChord`.

  The harmony layer describes music (note names), not performance
  (MIDI numbers, velocities, timing) — those belong to the machine and
  performance layers.
  """

  alias Mensch.Harmony.{ChordSpec, ResolvedChord, Scale}

  @chord_tones %{
    maj7: [0, 4, 7, 11],
    maj9: [0, 4, 7, 11, 14],
    maj11: [0, 4, 7, 11, 14, 17],
    maj13: [0, 4, 7, 11, 14, 17, 21],
    dom7: [0, 4, 7, 10],
    dom9: [0, 4, 7, 10, 14],
    dom11: [0, 4, 7, 10, 14, 17],
    dom13: [0, 4, 7, 10, 14, 17, 21],
    min7: [0, 3, 7, 10],
    min9: [0, 3, 7, 10, 14],
    min11: [0, 3, 7, 10, 14, 17],
    min13: [0, 3, 7, 10, 14, 17, 21],
    m7b5: [0, 3, 6, 10]
  }

  @doc "Returns all known chord modifier atoms (e.g. `:min7`, `:dom9`)."
  @spec modifiers() :: [ChordSpec.modifier()]
  def modifiers, do: Map.keys(@chord_tones)

  @doc "Returns the semitone intervals (from the chord root) for `modifier`."
  @spec chord_tones(ChordSpec.modifier()) :: [non_neg_integer()]
  def chord_tones(modifier), do: Map.fetch!(@chord_tones, modifier)

  @doc """
  Resolves `chord_spec` against `scale` into a `ResolvedChord`.

      iex> Mensch.Harmony.Resolver.resolve(%Mensch.Harmony.Scale{key: :c, mode: :major}, %Mensch.Harmony.ChordSpec{degree: :ii, modifier: :min7})
      %Mensch.Harmony.ResolvedChord{root: :d, notes: [:d, :f, :a, :c], degree: :ii, modifier: :min7}

  """
  @spec resolve(Scale.t(), ChordSpec.t()) :: ResolvedChord.t()
  def resolve(%Scale{} = scale, %ChordSpec{degree: degree, modifier: modifier}) do
    root = Scale.note_at_degree(scale, degree)
    notes = chord_tones(modifier) |> Enum.map(&Scale.transpose(root, &1))

    %ResolvedChord{root: root, notes: notes, degree: degree, modifier: modifier}
  end
end
