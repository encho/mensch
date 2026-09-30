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
  * `modulation_strategy`: Note modulation strategy struct used by this machine.
  """

  alias Mensch.Machines.DynamicVoicing.NoteModulationStrategies.DynamicVoicingEnvelopedPressure

  @allowed_modulation_strategy_modules [
    DynamicVoicingEnvelopedPressure
  ]

  @type direction :: :up | :down | {:cycle_up, pos_integer()} | {:cycle_down, pos_integer()}

  @type t :: %__MODULE__{
          direction: direction(),
          number_of_inversions: pos_integer(),
          modulation_strategy: struct()
        }

  @enforce_keys [:direction, :number_of_inversions, :modulation_strategy]
  defstruct [:direction, :number_of_inversions, :modulation_strategy]

  @doc "Default parameters for the dynamic voicing machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      direction: :up,
      number_of_inversions: 4,
      modulation_strategy: %DynamicVoicingEnvelopedPressure{error_prefix: "dynamic_voicing"}
    }
  end

  @doc "Allowed note modulation strategy modules for DynamicVoicing."
  @spec allowed_modulation_strategy_modules() :: [module()]
  def allowed_modulation_strategy_modules, do: @allowed_modulation_strategy_modules

  @doc "Validate that params use a DynamicVoicing-allowed modulation strategy module."
  @spec validate_modulation_strategy!(t()) :: t()
  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: %module{}} = params)
      when module in @allowed_modulation_strategy_modules,
      do: params

  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: %module{}}) do
    raise ArgumentError,
          "dynamic_voicing modulation_strategy must be one of #{inspect(@allowed_modulation_strategy_modules)}, got: #{inspect(module)}"
  end

  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: other}) do
    raise ArgumentError,
          "dynamic_voicing modulation_strategy must be a struct from #{inspect(@allowed_modulation_strategy_modules)}, got: #{inspect(other)}"
  end
end
