defmodule Mensch.Machines.RootNoteParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.RootNote`.

  Parameter reference:

  * `octave_offset`: Whole-octave transposition relative to the chord octave.
    This does not alter harmonic identity and is independent from chord
    inversion.
  * `velocity`: MIDI note-on velocity (`0..127`).
  * `pressure`: Legacy field kept for compatibility. RootNote rendering uses a
    fixed pressure baseline of `0`, so any non-zero pressure comes from
    `lfo_pressure`.
  * `lfo_pressure`: Pressure modulation config represented as
    `%{lfo: lfo_term, mode: :add | :multiply}`.
  """

  alias Mensch.Modulation
  alias Mensch.Modulation.LfoCurve
  alias Mensch.Modulation.LfoGroup

  @type lfo_pressure :: Modulation.lfo_pressure()

  @type t :: %__MODULE__{
          octave_offset: integer(),
          velocity: non_neg_integer(),
          pressure: non_neg_integer(),
          lfo_pressure: lfo_pressure()
        }

  @enforce_keys [
    :octave_offset,
    :velocity,
    :pressure,
    :lfo_pressure
  ]
  defstruct [
    :octave_offset,
    :velocity,
    pressure: 0,
    lfo_pressure: %{lfo: %LfoGroup{initial: %LfoCurve{}}, mode: :add}
  ]

  @doc "Default parameters for the root note machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      octave_offset: 0,
      velocity: 100,
      pressure: 0,
      lfo_pressure: %{lfo: LfoGroup.default(), mode: :add}
    }
  end
end
