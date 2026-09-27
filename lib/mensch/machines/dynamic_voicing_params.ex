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
  Pressure envelope timings and modulation lanes are not part of params for
  this machine. They are computed internally in `with_note_modulators/2`.
  """

  @type direction :: :up | :down | {:cycle_up, pos_integer()} | {:cycle_down, pos_integer()}

  @type t :: %__MODULE__{
          direction: direction(),
          number_of_inversions: pos_integer()
        }

  @enforce_keys [:direction, :number_of_inversions]
  defstruct [:direction, :number_of_inversions]

  @doc "Default parameters for the dynamic voicing machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      direction: :up,
      number_of_inversions: 4
    }
  end
end
