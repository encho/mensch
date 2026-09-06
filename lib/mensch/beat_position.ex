defmodule Mensch.BeatPosition do
  @moduledoc """
  Human-readable musical position on a sample grid.

  Bars are zero-based (`bar: 0` is the first bar), as requested.
  `beat` is zero-based within the bar, and `tick` is the fine PPQ
  subdivision within a beat.
  """

  @type t :: %__MODULE__{bar: non_neg_integer(), beat: non_neg_integer(), tick: non_neg_integer()}

  @enforce_keys [:bar, :beat, :tick]
  defstruct [:bar, :beat, :tick]

  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def new(bar, beat, tick)
      when is_integer(bar) and bar >= 0 and is_integer(beat) and beat >= 0 and is_integer(tick) and
             tick >= 0 do
    %__MODULE__{bar: bar, beat: beat, tick: tick}
  end
end
