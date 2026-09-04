defmodule Mensch.Trig do
  @moduledoc """
  A single step slot on a track.

  For now a trig only tracks its position and whether it is enabled.
  Parameter locks are intentionally not modeled yet.
  """

  defstruct [:step, enabled: false]

  @type t :: %__MODULE__{step: pos_integer(), enabled: boolean()}

  @doc "Builds a disabled trig for the given step (1-based)."
  @spec new(pos_integer()) :: t()
  def new(step) when is_integer(step) and step > 0 do
    %__MODULE__{step: step, enabled: false}
  end

  @doc "Flips the enabled state of a trig."
  @spec toggle(t()) :: t()
  def toggle(%__MODULE__{enabled: enabled} = trig) do
    %{trig | enabled: !enabled}
  end
end
