defmodule Mensch.Machines.RootNoteParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.RootNote`.

  Parameter reference:

  * `octave_offset`: Whole-octave transposition relative to the chord octave.
    This does not alter harmonic identity and is independent from chord
    inversion.
  * `velocity`: MIDI note-on velocity (`0..127`).
  * `pressure`: Legacy field kept for compatibility. RootNote rendering uses a
    fixed pressure baseline of `0`.
  * `modulation_strategy`: Note modulation strategy struct used by this machine.
  """

  alias Mensch.Machines.RootNote.NoteModulationStrategies.EnvelopedPressure

  @type t :: %__MODULE__{
          octave_offset: integer(),
          velocity: non_neg_integer(),
          pressure: non_neg_integer(),
          modulation_strategy: struct()
        }

  @enforce_keys [:octave_offset, :velocity, :pressure, :modulation_strategy]
  defstruct [:octave_offset, :velocity, :modulation_strategy, pressure: 0]

  @doc "Default parameters for the root note machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      octave_offset: 0,
      velocity: 100,
      pressure: 0,
      modulation_strategy: %EnvelopedPressure{error_prefix: "root_note"}
    }
  end
end
