defmodule Mensch.Machines.PulseRootParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.PulseRoot`.

  Parameter reference:

  * `velocity`: MIDI note-on velocity (`0..127`).
  * `base_pressure`: Pressure value outside pulse windows (`0..127`).
  * `peak_pressure`: Pressure value at beat-aligned pulse peaks (`0..127`).
  * `pulse_width_mbeats`: Pulse decay window after each beat in millibeats.
  """

  @type t :: %__MODULE__{
          velocity: non_neg_integer(),
          base_pressure: non_neg_integer(),
          peak_pressure: non_neg_integer(),
          pulse_width_mbeats: pos_integer()
        }

  @enforce_keys [:velocity, :base_pressure, :peak_pressure, :pulse_width_mbeats]
  defstruct [:velocity, :base_pressure, :peak_pressure, :pulse_width_mbeats]

  @doc "Returns baseline pulse-root machine parameters used in sample definitions."
  @spec default() :: t()
  def default do
    %__MODULE__{
      velocity: 100,
      base_pressure: 30,
      peak_pressure: 95,
      pulse_width_mbeats: 120
    }
  end
end
