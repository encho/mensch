defmodule Mensch.Performance.Event do
  @moduledoc """
  A neutral, MIDI-agnostic representation of something that should
  happen in musical time.

  Positions are expressed in beats, not milliseconds — the performance
  layer does not depend on BPM for its basic timeline representation.

  `:note_on`/`:note_off` start and stop a note. `:pressure` and
  `:pitch_bend` are per-note expression (MPE-style modulation) applied
  to the currently sounding note — their `value` is a float rather
  than a MIDI velocity.
  """

  defstruct [:type, :at_beat, :note, :velocity, :value]

  @type note :: {Mensch.Harmony.Key.note(), non_neg_integer()}

  @type t :: %__MODULE__{
          type: :note_on | :note_off | :pressure | :pitch_bend,
          at_beat: float(),
          note: note(),
          velocity: 0..127 | nil,
          value: float() | nil
        }
end
