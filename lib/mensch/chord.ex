defmodule Mensch.Chord do
  @moduledoc """
  Pure value representing a chord: a key, a scale degree (e.g. `:ii`,
  `:V`), a quality modifier (e.g. `:min7`, `:maj7`), and the octave to
  play it in, resolved down to concrete chord tones.

  Just data - no process, and no notion of tempo, timing, or how long
  it should sound. See `Mensch.ChordPlayer` for actually playing a
  chord over MIDI, and `Mensch.Tempo` / `Mensch.Timing` for
  tempo/timing concerns.
  """

  alias Mensch.Harmony.{ChordSpec, Key, Resolver}

  defstruct [:key, :degree, :modifier, :octave, :resolved]

  @doc """
  Builds a `%Mensch.Chord{}`, resolving `degree` and `modifier`
  against `key` (see `Mensch.Harmony.Resolver`).
  """
  def new(%Key{} = key, degree, modifier, octave) do
    resolved = Resolver.resolve(key, %ChordSpec{degree: degree, modifier: modifier})

    %__MODULE__{
      key: key,
      degree: degree,
      modifier: modifier,
      octave: octave,
      resolved: resolved
    }
  end

  @doc "The chord tones (list of note atoms, e.g. `[:c, :e, :g, :b]`)."
  def notes(%__MODULE__{resolved: resolved}), do: resolved.notes
end
