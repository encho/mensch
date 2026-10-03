defmodule Mensch.Machines.StrumParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.Strum`.

  Parameter reference:

  * `velocity`: MIDI note-on velocity (`0..127`) applied to all chord tones.
  * `modulation_strategy`: Note modulation strategy struct used by this machine.
  """

  alias Mensch.Machines.Strum.NoteModulationStrategies.StrumEnvelopedPressure

  @allowed_modulation_strategy_modules [
    StrumEnvelopedPressure
  ]

  @type t :: %__MODULE__{
          velocity: non_neg_integer(),
          modulation_strategy: struct()
        }

  @enforce_keys [:velocity, :modulation_strategy]
  defstruct [:velocity, :modulation_strategy]

  @doc "Default parameters for the strum machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      velocity: 100,
      modulation_strategy: %StrumEnvelopedPressure{error_prefix: "strum"}
    }
  end

  @doc "Allowed note modulation strategy modules for Strum."
  @spec allowed_modulation_strategy_modules() :: [module()]
  def allowed_modulation_strategy_modules, do: @allowed_modulation_strategy_modules

  @doc "Validate that params use a Strum-allowed modulation strategy module."
  @spec validate_modulation_strategy!(t()) :: t()
  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: %module{}} = params)
      when module in @allowed_modulation_strategy_modules,
      do: params

  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: %module{}}) do
    raise ArgumentError,
          "strum modulation_strategy must be one of #{inspect(@allowed_modulation_strategy_modules)}, got: #{inspect(module)}"
  end

  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: other}) do
    raise ArgumentError,
          "strum modulation_strategy must be a struct from #{inspect(@allowed_modulation_strategy_modules)}, got: #{inspect(other)}"
  end
end
