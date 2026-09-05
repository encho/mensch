defmodule Mensch.Sequencer do
  @moduledoc """
  Global chord-progression loop.

  Holds an ordered list of `{%Mensch.Chord{}, %Mensch.Envelope{}}`
  steps and cycles through them forever: each step plays for its own
  envelope's `:duration_bars`, then the loop automatically advances to
  the next step, wrapping back to the first after the last. PLAY
  (`play/1`) (re)starts the loop from the first step; STOP (`stop/0`)
  halts everything immediately, wherever the loop currently is.

  Advancing is fire-and-forget: the loop never waits for (or stops)
  the step it's leaving before starting the next one, so a step's own
  release fade (see `Mensch.ChordPlayer`) always finishes on its own
  time, asynchronously, in the background - the only hard guarantee is
  that every step starts exactly on schedule. Every chord the loop has
  ever started (the current one, plus any still-releasing stragglers)
  is tracked and monitored, so STOP can still kill everything at once,
  instantly, with no fade.
  """

  use GenServer

  alias Mensch.ChordPlayer
  alias Mensch.ChordSupervisor
  alias Mensch.Timing

  defstruct steps: [],
            status: :stopped,
            index: 0,
            current_pid: nil,
            chord_pids: [],
            timing: nil,
            timer_ref: nil

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  (Re)starts the loop from the first of `steps` (a list of
  `{%Mensch.Chord{}, %Mensch.Envelope{}}` pairs).
  """
  def play(steps) when is_list(steps) and steps != [] do
    GenServer.call(__MODULE__, {:play, steps})
  end

  @doc "Stops the loop immediately, wherever it currently is."
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Returns a snapshot: `%{status:, index:, bars_per_step:, bar:, progress:, notes:}`.

  `index` is the (0-based) currently playing step, `bar` is the
  current (1-based) bar within that step's `bars_per_step`,
  `progress` is how far (0.0..1.0) the loop as a whole has gotten
  through a full cycle of every step, and `notes` is the currently
  sounding chord's note info (see `Mensch.ChordPlayer.snapshot/1`) -
  empty when stopped.
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
  def handle_call({:play, steps}, _from, state) do
    state =
      state
      |> stop_all()
      |> Map.merge(%{steps: steps, status: :playing, index: 0})
      |> start_step()

    {:reply, :ok, state}
  end

  def handle_call(:stop, _from, state) do
    state = state |> stop_all() |> Map.merge(%{status: :stopped, index: 0})
    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, build_snapshot(state), state}
  end

  @impl true
  def handle_info({:advance, ref}, %{timer_ref: ref, status: :playing} = state) do
    next_index = rem(state.index + 1, length(state.steps))

    state =
      state
      |> Map.put(:index, next_index)
      |> start_step()

    {:noreply, state}
  end

  # Stale timer from a step we already advanced past - ignore.
  def handle_info({:advance, _ref}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | chord_pids: List.delete(state.chord_pids, pid)}}
  end

  defp start_step(%{steps: steps, index: index} = state) do
    {chord, envelope} = Enum.at(steps, index)
    timing = Timing.now()
    {:ok, pid} = ChordSupervisor.start_chord(chord: chord, envelope: envelope, timing: timing)
    Process.monitor(pid)
    ref = make_ref()
    Process.send_after(self(), {:advance, ref}, Timing.bars_to_ms(timing, envelope.duration_bars))

    %{
      state
      | current_pid: pid,
        chord_pids: [pid | state.chord_pids],
        timing: timing,
        timer_ref: ref
    }
  end

  defp stop_all(state) do
    Enum.each(state.chord_pids, fn pid ->
      if Process.alive?(pid), do: ChordSupervisor.stop_chord(pid)
    end)

    %{state | chord_pids: [], current_pid: nil, timing: nil, timer_ref: nil}
  end

  defp build_snapshot(%{status: :stopped}), do: stopped_snapshot()

  defp build_snapshot(%{status: :playing} = state) do
    {_chord, envelope} = Enum.at(state.steps, state.index)
    bar_ms = Timing.bars_to_ms(state.timing, 1)
    elapsed_bars = div(Timing.elapsed_ms(state.timing), bar_ms)
    bar = min(envelope.duration_bars, elapsed_bars + 1)
    step_progress = ChordPlayer.progress(state.current_pid) || 0.0
    progress = (state.index + step_progress) / length(state.steps)

    %{
      status: :playing,
      index: state.index,
      bars_per_step: envelope.duration_bars,
      bar: bar,
      progress: progress,
      notes: ChordPlayer.snapshot(state.current_pid)
    }
  end

  defp stopped_snapshot do
    %{status: :stopped, index: 0, bars_per_step: 4, bar: 1, progress: 0.0, notes: []}
  end
end
