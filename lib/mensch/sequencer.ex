defmodule Mensch.Sequencer do
  @moduledoc """
  Global chord-progression loop.

  Holds an ordered list of `%Mensch.Chord{}` steps and cycles through
  them forever: each step plays for 4 bars, then the loop
  automatically advances to the next step, wrapping back to the first
  after the last. PLAY (`play/1`) (re)starts the loop from the first
  step; STOP (`stop/0`) halts everything immediately, wherever the
  loop currently is - it is never blocked by a step "still running".

  This is the global scheduler alluded to in `Mensch.Tempo` and
  `Mensch.ChordPlayer`'s docs: the loop itself owns all scheduling
  and bar-position bookkeeping, so each step's `Mensch.ChordPlayer` is
  simply told to hold indefinitely (`duration_bars: 0`) and is
  explicitly stopped by the loop - never by itself - when it's time to
  advance.
  """

  use GenServer

  alias Mensch.ChordPlayer
  alias Mensch.ChordSupervisor
  alias Mensch.Timing

  @bars_per_step 4

  defstruct chords: [],
            status: :stopped,
            index: 0,
            chord_pid: nil,
            timing: nil,
            timer_ref: nil

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "(Re)starts the loop from the first of `chords` (a list of `%Mensch.Chord{}`)."
  def play(chords) when is_list(chords) and chords != [] do
    GenServer.call(__MODULE__, {:play, chords})
  end

  @doc "Stops the loop immediately, wherever it currently is."
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Returns a snapshot: `%{status:, index:, bars_per_step:, bar:, notes:}`.

  `index` is the (0-based) currently playing step, `bar` is the
  current (1-based) bar within that step's `bars_per_step`, and
  `notes` is the currently sounding chord's note info (see
  `Mensch.ChordPlayer.snapshot/1`) - empty when stopped.
  """
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  catch
    :exit, _ -> stopped_snapshot()
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:play, chords}, _from, state) do
    state =
      state
      |> stop_current_step()
      |> Map.merge(%{chords: chords, status: :playing, index: 0})
      |> start_step()

    {:reply, :ok, state}
  end

  def handle_call(:stop, _from, state) do
    state =
      state
      |> stop_current_step()
      |> Map.merge(%{status: :stopped, index: 0})

    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, build_snapshot(state), state}
  end

  @impl true
  def handle_info({:advance, ref}, %{timer_ref: ref, status: :playing} = state) do
    next_index = rem(state.index + 1, length(state.chords))

    state =
      state
      |> stop_current_step()
      |> Map.put(:index, next_index)
      |> start_step()

    {:noreply, state}
  end

  # Stale timer from a step we already advanced/stopped past - ignore.
  def handle_info({:advance, _ref}, state), do: {:noreply, state}

  defp start_step(%{chords: chords, index: index} = state) do
    chord = Enum.at(chords, index)
    {:ok, pid} = ChordSupervisor.start_chord(chord: chord, duration_bars: 0)
    timing = Timing.now()
    ref = make_ref()
    Process.send_after(self(), {:advance, ref}, Timing.bars_to_ms(timing, @bars_per_step))
    %{state | chord_pid: pid, timing: timing, timer_ref: ref}
  end

  defp stop_current_step(state) do
    if is_pid(state.chord_pid) and Process.alive?(state.chord_pid) do
      ChordSupervisor.stop_chord(state.chord_pid)
    end

    %{state | chord_pid: nil, timing: nil, timer_ref: nil}
  end

  defp build_snapshot(%{status: :stopped}), do: stopped_snapshot()

  defp build_snapshot(%{status: :playing} = state) do
    bar_ms = Timing.bars_to_ms(state.timing, 1)
    elapsed_bars = div(Timing.elapsed_ms(state.timing), bar_ms)
    bar = min(@bars_per_step, elapsed_bars + 1)

    %{
      status: :playing,
      index: state.index,
      bars_per_step: @bars_per_step,
      bar: bar,
      notes: ChordPlayer.snapshot(state.chord_pid)
    }
  end

  defp stopped_snapshot do
    %{status: :stopped, index: 0, bars_per_step: @bars_per_step, bar: 1, notes: []}
  end
end
