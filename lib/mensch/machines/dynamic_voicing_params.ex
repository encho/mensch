defmodule Mensch.Machines.DynamicVoicingParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.DynamicVoicing`.

  Parameter reference:

  * `direction`: Inversion motion direction (`:up`, `:down`, `{:cycle_up, n}`,
    or `{:cycle_down, n}` where `n` is the number of full bounce cycles).
  * `number_of_inversions`: For `:up`/`:down`, total number of voicings to
    play, including the first/base voicing. For cycle modes, total voicing
    states in each up/down leg including both endpoints (start and turnaround),
    so `4` means four visible states per leg. Must be >= 2 in cycle modes.
    If requested voicings do not fit the chord duration frame budget,
    validation fails with an error.
  * `lfo_pressure`: Pressure LFO settings.
  * `lfo_slide`: Slide (CC74) LFO settings. Applied additively to the
    baseline slide value using a unipolar waveform (never below 0).
  """

  alias Mensch.LfoParams

  @type direction :: :up | :down | {:cycle_up, pos_integer()} | {:cycle_down, pos_integer()}

  @type t :: %__MODULE__{
          direction: direction(),
          number_of_inversions: pos_integer(),
          lfo_pressure: LfoParams.t(),
          lfo_slide: LfoParams.t()
        }

  @enforce_keys [:direction, :number_of_inversions]
  defstruct [
    :direction,
    :number_of_inversions,
    lfo_pressure: %LfoParams{},
    lfo_slide: %LfoParams{}
  ]

  @doc "Default parameters for the dynamic voicing machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      direction: :up,
      number_of_inversions: 4,
      lfo_pressure: LfoParams.default(),
      lfo_slide: LfoParams.default()
    }
  end
end
