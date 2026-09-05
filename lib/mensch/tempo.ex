defmodule Mensch.Tempo do
  @moduledoc """
  Holds the global tempo (BPM) used to translate musical durations
  (bars) into wall-clock milliseconds.

  Tempo is deliberately global, singleton state - not something owned
  by any one `Mensch.ChordPlayer` - because it's a property of the
  whole performance/session, the same way a single tempo/clock knob on
  a piece of hardware is shared by everything it drives. Every
  chord's duration, and later a global scheduler that triggers chords
  at specific musical points (e.g. "start this chord on the next
  bar"), is measured against this one shared clock.

  Defaults to 120 BPM in 4/4 time (`beats_per_bar/0`).
  """

  use GenServer

  @default_bpm 120
  @beats_per_bar 4

  defstruct bpm: @default_bpm

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the current global BPM."
  @spec bpm() :: number()
  def bpm, do: GenServer.call(__MODULE__, :bpm)

  @doc "Sets the current global BPM. Must be a positive number."
  @spec set_bpm(number()) :: :ok
  def set_bpm(bpm) when is_number(bpm) and bpm > 0 do
    GenServer.call(__MODULE__, {:set_bpm, bpm})
  end

  @doc "Beats per bar for the current (fixed, 4/4) time signature."
  @spec beats_per_bar() :: pos_integer()
  def beats_per_bar, do: @beats_per_bar

  @doc "Milliseconds per beat at the current global BPM."
  @spec beat_duration_ms() :: float()
  def beat_duration_ms, do: beat_duration_ms(bpm())

  @doc "Milliseconds per bar at the current global BPM."
  @spec bar_duration_ms() :: float()
  def bar_duration_ms, do: bar_duration_ms(bpm())

  @doc """
  Converts a duration in bars (may be fractional, e.g. `0.5` for half
  a bar) to milliseconds at the current global BPM, rounded to the
  nearest millisecond.
  """
  @spec bars_to_ms(number()) :: non_neg_integer()
  def bars_to_ms(bars) when is_number(bars) and bars >= 0, do: bars_to_ms(bars, bpm())

  @doc "Milliseconds per beat at the given `bpm`. Pure - ignores global state."
  @spec beat_duration_ms(number()) :: float()
  def beat_duration_ms(bpm) when is_number(bpm) and bpm > 0, do: 60_000 / bpm

  @doc "Milliseconds per bar at the given `bpm`. Pure - ignores global state."
  @spec bar_duration_ms(number()) :: float()
  def bar_duration_ms(bpm) when is_number(bpm) and bpm > 0 do
    beat_duration_ms(bpm) * @beats_per_bar
  end

  @doc "Converts `bars` to milliseconds at the given `bpm`. Pure - ignores global state."
  @spec bars_to_ms(number(), number()) :: non_neg_integer()
  def bars_to_ms(bars, bpm)
      when is_number(bars) and bars >= 0 and is_number(bpm) and bpm > 0 do
    round(bars * bar_duration_ms(bpm))
  end

  # Server callbacks

  @impl true
  def init(opts) do
    bpm = Keyword.get(opts, :bpm, @default_bpm)
    {:ok, %__MODULE__{bpm: bpm}}
  end

  @impl true
  def handle_call(:bpm, _from, state), do: {:reply, state.bpm, state}

  def handle_call({:set_bpm, bpm}, _from, state) do
    {:reply, :ok, %{state | bpm: bpm}}
  end
end
