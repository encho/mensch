defmodule Mensch.Machines.RootModulatedParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.RootModulated`.

  Parameter reference:

  * `velocity`: MIDI note-on velocity (`0..127`).
  * `attack_mbeats`: Envelope attack duration in millibeats.
  * `decay_mbeats`: Envelope decay duration in millibeats.
  * `release_mbeats`: Envelope release duration in millibeats.
  """

  @type t :: %__MODULE__{
          velocity: non_neg_integer(),
          attack_mbeats: non_neg_integer(),
          decay_mbeats: non_neg_integer(),
          release_mbeats: non_neg_integer()
        }

  @enforce_keys [:velocity, :attack_mbeats, :decay_mbeats, :release_mbeats]
  defstruct [:velocity, :attack_mbeats, :decay_mbeats, :release_mbeats]

  @doc "Returns baseline root-modulated machine parameters used in sample definitions."
  @spec default() :: t()
  def default do
    %__MODULE__{
      velocity: 100,
      attack_mbeats: 1000,
      decay_mbeats: 200,
      release_mbeats: 1000
    }
  end
end
