defmodule Mensch.LfoParams do
  @moduledoc """
  Shared LFO settings for modulation sources.
  """

  @type curve :: :sine | :triangle | :saw_up | :saw_down | :square
  @type time_base :: :absolute | :entry_local
  @type mode :: :additive | :multiplicative

  @type t :: %__MODULE__{
          curve: curve(),
          scale: float(),
          cycles_per_bar: float(),
          shift_mbeats: number(),
          time_base: time_base(),
          mode: mode()
        }

  defstruct curve: :sine,
            scale: 0.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            time_base: :absolute,
            mode: :additive

  @spec default() :: t()
  def default, do: %__MODULE__{}
end
