defmodule Mensch.Machines.ChordParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.Chord`.

  Parameter reference:

  * `velocity`: MIDI note-on velocity (`0..127`) applied to all chord tones.
  * `modulation_strategy`: Note modulation strategy struct used by this machine.
  """

  alias Mensch.Machines.Chord.NoteModulationStrategies.ChordEnvelopedPressure

  @allowed_modulation_strategy_modules [
    ChordEnvelopedPressure
  ]

  @type t :: %__MODULE__{
          velocity: non_neg_integer(),
          modulation_strategy: struct()
        }

  @enforce_keys [:velocity, :modulation_strategy]
  defstruct [:velocity, :modulation_strategy]

  @doc "Default parameters for the chord machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      velocity: 100,
      modulation_strategy: %ChordEnvelopedPressure{error_prefix: "chord"}
    }
  end

  @doc "Allowed note modulation strategy modules for Chord."
  @spec allowed_modulation_strategy_modules() :: [module()]
  def allowed_modulation_strategy_modules, do: @allowed_modulation_strategy_modules

  @doc "Validate that params use a Chord-allowed modulation strategy module."
  @spec validate_modulation_strategy!(t()) :: t()
  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: %module{}} = params)
      when module in @allowed_modulation_strategy_modules,
      do: params

  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: %module{}}) do
    raise ArgumentError,
          "chord modulation_strategy must be one of #{inspect(@allowed_modulation_strategy_modules)}, got: #{inspect(module)}"
  end

  def validate_modulation_strategy!(%__MODULE__{modulation_strategy: other}) do
    raise ArgumentError,
          "chord modulation_strategy must be a struct from #{inspect(@allowed_modulation_strategy_modules)}, got: #{inspect(other)}"
  end
end
