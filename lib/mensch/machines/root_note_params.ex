defmodule Mensch.Machines.RootNoteParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.RootNote`.

  Parameter reference:

  * `octave_offset`: Whole-octave transposition relative to the chord octave.
    This does not alter harmonic identity and is independent from chord
    inversion.
  * `velocity`: MIDI note-on velocity (`0..127`).
  * `pressure`: Constant pressure value held for the full note (`0..127`).
  """

  @type t :: %__MODULE__{
          octave_offset: integer(),
          velocity: non_neg_integer(),
          pressure: non_neg_integer()
        }

  @enforce_keys [
    :octave_offset,
    :velocity,
    :pressure
  ]
  defstruct [
    :octave_offset,
    :velocity,
    :pressure
  ]

  @doc "Default parameters for the root note machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      octave_offset: 0,
      velocity: 100,
      pressure: 80
    }
  end
end
