defmodule Mensch.Machine do
  @moduledoc """
  A machine defines default musical parameters for a track.

  Parameters are defaults only; a trig may override them via parameter
  locks (see `Mensch.Trig` and `Mensch.ParameterResolver`).
  """

  defstruct expression: 0.6, pressure: 0.5, duration: {:beats, 1}, release: {:beats, 0.5}

  @type musical_time :: {:beats, number()}

  @type t :: %__MODULE__{
          expression: float(),
          pressure: float(),
          duration: musical_time(),
          release: musical_time()
        }

  @doc "Builds a machine with default parameters."
  @spec new() :: t()
  def new, do: %__MODULE__{}
end
