defmodule Mensch.Machines.RootNoteParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.RootNote`.

  Parameter reference:

  * `octave_offset`: Whole-octave transposition relative to the chord octave.
    This does not alter harmonic identity and is independent from chord
    inversion.
  * `velocity`: MIDI note-on velocity (`0..127`).
  * `pressure`: Constant baseline pressure value held for the full note
    (`0..127`) before LFO modulation is applied.
  * `lfo_pressure`: Pressure modulation config represented as
    `%{lfo: lfo_term, mode: :add | :multiply}`.
  """

  alias Mensch.NewModulation
  alias Mensch.NewModulation.LfoCurve
  alias Mensch.NewModulation.LfoGroup

  @type lfo_pressure :: NewModulation.lfo_pressure()

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
    :pressure,
    lfo_pressure: %{lfo: %LfoGroup{initial: %LfoCurve{}}, mode: :additive}
  ]

  @doc "Default parameters for the root note machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      octave_offset: 0,
      velocity: 100,
      pressure: 80,
      lfo_pressure: %{lfo: LfoGroup.default(), mode: :add}
    }
  end
end
