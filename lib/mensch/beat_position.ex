defmodule Mensch.BeatPosition do
  @moduledoc """
  Human-readable musical position on a sample grid.

  Bars are zero-based (`bar: 0` is the first bar), as requested.
  `beat` is zero-based within the bar, and `mbeat` is the fine
  subdivision within a beat (0..999 millibeats).
  """

  @type t :: %__MODULE__{
          bar: non_neg_integer(),
          beat: non_neg_integer(),
          mbeat: non_neg_integer()
        }

  @enforce_keys [:bar, :beat, :mbeat]
  defstruct [:bar, :beat, :mbeat]

  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def new(bar, beat, mbeat)
      when is_integer(bar) and bar >= 0 and is_integer(beat) and beat >= 0 and
             is_integer(mbeat) and mbeat >= 0 and mbeat < 1000 do
    %__MODULE__{bar: bar, beat: beat, mbeat: mbeat}
  end
end
