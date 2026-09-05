defmodule Mensch.Harmony.ChordSpec do
  @moduledoc """
  Immutable, deterministic description of a chord within a progression:
  a roman-numeral scale degree plus a quality modifier.

  A `ChordSpec` is pure data — it is resolved against a `Key` by
  `Mensch.Harmony.Resolver` into a `Mensch.Harmony.ResolvedChord`.
  """

  defstruct [:degree, :modifier]

  @type degree ::
          :i | :ii | :iii | :iv | :v | :vi | :vii | :I | :II | :III | :IV | :V | :VI | :VII
  @type modifier ::
          :maj7
          | :maj9
          | :maj11
          | :maj13
          | :dom7
          | :dom9
          | :dom11
          | :dom13
          | :min7
          | :min9
          | :min11
          | :min13
          | :m7b5

  @type t :: %__MODULE__{degree: degree(), modifier: modifier()}
end
