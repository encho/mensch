defmodule Mensch.Machines.DynamicVoicingParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.DynamicVoicing`.

  Parameter reference:

  * `direction`: Inversion motion direction (`:up` or `:down`).
  * `number_of_inversions`: Total number of voicings to play, including the
    first/base voicing. Must be >= 1.
  * `pressure_lfo_curve`: Pressure LFO waveform.
  * `pressure_lfo_scale`: Additional LFO modulation scale.
  * `pressure_lfo_cycles_per_bar`: LFO cycles per bar.
  * `pressure_lfo_shift_mbeats`: Horizontal LFO shift in mbeats.
  * `pressure_lfo_time_base`: Time base for bar phase (`:absolute` or
    `:entry_local`).
  * `pressure_lfo_mode`: Modulation mode (`:additive` or `:multiplicative`).
  """

  @type direction :: :up | :down
  @type pressure_lfo_curve :: :sine | :triangle | :saw_up | :saw_down | :square
  @type pressure_lfo_time_base :: :absolute | :entry_local
  @type pressure_lfo_mode :: :additive | :multiplicative

  @type t :: %__MODULE__{
          direction: direction(),
          number_of_inversions: pos_integer(),
          pressure_lfo_curve: pressure_lfo_curve(),
          pressure_lfo_scale: float(),
          pressure_lfo_cycles_per_bar: float(),
          pressure_lfo_shift_mbeats: number(),
          pressure_lfo_time_base: pressure_lfo_time_base(),
          pressure_lfo_mode: pressure_lfo_mode()
        }

  @enforce_keys [:direction, :number_of_inversions]
  defstruct [
    :direction,
    :number_of_inversions,
    pressure_lfo_curve: :sine,
    pressure_lfo_scale: 0.0,
    pressure_lfo_cycles_per_bar: 1.0,
    pressure_lfo_shift_mbeats: 0.0,
    pressure_lfo_time_base: :absolute,
    pressure_lfo_mode: :additive
  ]

  @doc "Default parameters for the dynamic voicing machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      direction: :up,
      number_of_inversions: 4,
      pressure_lfo_curve: :sine,
      pressure_lfo_scale: 0.0,
      pressure_lfo_cycles_per_bar: 1.0,
      pressure_lfo_shift_mbeats: 0.0,
      pressure_lfo_time_base: :absolute,
      pressure_lfo_mode: :additive
    }
  end
end
