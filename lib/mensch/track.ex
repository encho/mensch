defmodule Mensch.Track do
  @moduledoc """
  A track holds 16 trigs.
  """

  alias Mensch.Trig

  defstruct [:id, :name, trigs: []]

  @type t :: %__MODULE__{id: pos_integer(), name: String.t(), trigs: [Trig.t()]}

  @trig_count 16

  @doc "Builds a track with #{@trig_count} disabled trigs."
  @spec new(pos_integer(), String.t()) :: t()
  def new(id, name) do
    trigs = for step <- 1..@trig_count, do: Trig.new(step)
    %__MODULE__{id: id, name: name, trigs: trigs}
  end

  @doc "Toggles the trig at the given step (1-based)."
  @spec toggle_trig(t(), pos_integer()) :: t()
  def toggle_trig(%__MODULE__{trigs: trigs} = track, step) do
    trigs =
      Enum.map(trigs, fn
        %Trig{step: ^step} = trig -> Trig.toggle(trig)
        trig -> trig
      end)

    %{track | trigs: trigs}
  end
end
