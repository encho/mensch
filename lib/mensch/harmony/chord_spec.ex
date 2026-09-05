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
  @type modifier :: :min7 | :dom7 | :maj7

  @type t :: %__MODULE__{degree: degree(), modifier: modifier()}
end
