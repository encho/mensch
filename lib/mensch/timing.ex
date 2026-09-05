defmodule Mensch.Timing do
  @moduledoc """
  A point-in-time snapshot of the global tempo/clock.

  Captured once when a `Mensch.ChordPlayer` starts, so it has a fixed
  reference to translate its own `:duration_bars` into milliseconds -
  protecting an already-playing chord from being thrown off by a later
  `Mensch.Tempo.set_bpm/1` call - and, later, so a global scheduler can
  reason about "where we are, timing-wise" relative to when playback
  started, e.g. to align the next chord to a bar boundary.
  """

  alias Mensch.Tempo

  defstruct [:bpm, :beats_per_bar, :started_at]

  @doc "Captures the current global tempo, timestamped now."
  def now do
    %__MODULE__{
      bpm: Tempo.bpm(),
      beats_per_bar: Tempo.beats_per_bar(),
      started_at: System.monotonic_time(:millisecond)
    }
  end

  @doc "Converts `bars` (musical time) to milliseconds, using this snapshot's bpm."
  def bars_to_ms(%__MODULE__{bpm: bpm}, bars), do: Tempo.bars_to_ms(bars, bpm)

  @doc "Milliseconds elapsed since this snapshot was captured."
  def elapsed_ms(%__MODULE__{started_at: started_at}) do
    System.monotonic_time(:millisecond) - started_at
  end
end
