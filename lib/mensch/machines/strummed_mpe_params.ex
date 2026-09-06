defmodule Mensch.Machines.StrummedMpeParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.StrummedMpe`.

  Parameter reference:

  * `velocity`: MIDI note-on velocity (`0..127`).
  * `attack_mbeats`: Envelope attack duration in millibeats.
  * `decay_mbeats`: Envelope decay duration in millibeats.
  * `release_mbeats`: Envelope release duration in millibeats.
  * `note_stagger_mbeats`: Delay between successive chord tones (strum spacing)
    in millibeats.
  """

  @type t :: %__MODULE__{
          velocity: non_neg_integer(),
          attack_mbeats: non_neg_integer(),
          decay_mbeats: non_neg_integer(),
          release_mbeats: non_neg_integer(),
          note_stagger_mbeats: non_neg_integer()
        }

  @enforce_keys [
    :velocity,
    :attack_mbeats,
    :decay_mbeats,
    :release_mbeats,
    :note_stagger_mbeats
  ]
  defstruct [
    :velocity,
    :attack_mbeats,
    :decay_mbeats,
    :release_mbeats,
    :note_stagger_mbeats
  ]

  @doc "Returns baseline strummed machine parameters used in sample definitions."
  @spec default() :: t()
  def default do
    %__MODULE__{
      velocity: 100,
      attack_mbeats: 1000,
      decay_mbeats: 200,
      release_mbeats: 1000,
      note_stagger_mbeats: 500
    }
  end
end
