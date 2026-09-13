defmodule Mensch.Machines.DynamicVoicingParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.DynamicVoicing`.

  Parameter reference:

  * `direction`: Inversion motion direction (`:up` or `:down`).
  * `number_of_inversions`: Total number of voicings to play, including the
    first/base voicing. Must be >= 1.
  """

  @type direction :: :up | :down

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
