defmodule Mensch.Machines.RootNoteParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.RootNote`.

  Parameter reference:

  * `octave_offset`: Whole-octave transposition relative to the chord octave.
    This does not alter harmonic identity and is independent from chord
    inversion.
  * `velocity`: MIDI note-on velocity (`0..127`).
  * `attack_mbeats`: Envelope attack duration in millibeats.
  * `decay_mbeats`: Envelope decay duration in millibeats.
  * `release_mbeats`: Envelope release duration in millibeats (`0` disables
    release phase and sustains until note-off).
  * `attack_curve`: Attack interpolation (`:linear`, `:exp`, `:log`, `:s_curve`).
  * `decay_curve`: Decay interpolation (`:linear`, `:exp`, `:log`, `:s_curve`).
  * `release_curve`: Release interpolation (`:linear`, `:exp`, `:log`, `:s_curve`).
  * `peak_level`: Peak envelope level (`0.0..1.0`).
  * `sustain_level`: Sustain envelope level (`0.0..1.0`).
  """

  @type curve :: :linear | :exp | :log | :s_curve

  @type t :: %__MODULE__{
          octave_offset: integer(),
          velocity: non_neg_integer(),
          attack_mbeats: non_neg_integer(),
          decay_mbeats: non_neg_integer(),
          release_mbeats: non_neg_integer(),
          attack_curve: curve(),
          decay_curve: curve(),
          release_curve: curve(),
          peak_level: float(),
          sustain_level: float()
        }

  @enforce_keys [
    :octave_offset,
    :velocity,
    :attack_mbeats,
    :decay_mbeats,
    :release_mbeats,
    :attack_curve,
    :decay_curve,
    :release_curve,
    :peak_level,
    :sustain_level
  ]
  defstruct [
    :octave_offset,
    :velocity,
    :attack_mbeats,
    :decay_mbeats,
    :release_mbeats,
    :attack_curve,
    :decay_curve,
    :release_curve,
    :peak_level,
    :sustain_level
  ]

  @doc "Default parameters for the root note machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      octave_offset: 0,
      velocity: 100,
      attack_mbeats: 80,
      decay_mbeats: 150,
      release_mbeats: 220,
      attack_curve: :linear,
      decay_curve: :linear,
      release_curve: :linear,
      peak_level: 1.0,
      sustain_level: 0.72
    }
  end
end
