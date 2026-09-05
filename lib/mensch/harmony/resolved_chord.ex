defmodule Mensch.Harmony.ResolvedChord do
  @moduledoc """
  The result of resolving a `Mensch.Harmony.ChordSpec` against a
  `Mensch.Harmony.Key`: a concrete root note plus the chord tones.

  MIDI note numbers are intentionally kept out of this layer — it
  describes music, not performance.
  """

  alias Mensch.Harmony.{ChordSpec, Key}

  defstruct [:root, :notes, :degree, :modifier]

  @type t :: %__MODULE__{
          root: Key.note(),
          notes: [Key.note()],
          degree: ChordSpec.degree(),
          modifier: ChordSpec.modifier()
        }
end
