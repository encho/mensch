defmodule Mensch.Player do
  @moduledoc """
  Plays a precomputed performance (see `Mensch.Render.generate/0`) in
  real time by dispatching each frame's MIDI messages to
  `Mensch.Midi.Connection` at the right scheduled offset.

  Deliberately just one process, not a supervision tree of per-note
  actors: since the whole performance is already known ahead of time,
  all that's left to do live is send the right bytes at the right
  moment, which a single process walking a fixed, precomputed event
  list can do on its own.

  A singleton, started once under the application supervisor (like
  `Mensch.Midi.Connection`) - not per-performance/ephemeral.
  """

  use GenServer

  alias Mensch.Midi.Connection

  defstruct status: :stopped, ref: nil, active: MapSet.new()

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts playing `data` (a `%Mensch.Performance{}` from
  `Mensch.Render.generate/0`) in real time,
  from right now. Stops (silencing) any performance already in
  progress first.
  """
  def play(data) do
    GenServer.call(__MODULE__, {:play, data})
  end

  @doc """
  Stops playback immediately, sending Note Off for every currently-
  sounding note.
  """
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc "Returns `:playing` or `:stopped`."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server callbacks

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{}}

  @impl true
  def handle_call({:play, data}, _from, state) do
    state = stop_all(state)
    ref = make_ref()

    Enum.each(data.music, fn frame ->
      Process.send_after(self(), {:frame, ref, frame.notes}, frame.at_ms)
    end)

    Process.send_after(self(), {:done, ref}, data.duration_ms + data.granularity_ms)

    {:reply, :ok, %{state | status: :playing, ref: ref}}
  end

  def handle_call(:stop, _from, state) do
    {:reply, :ok, stop_all(state)}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({:frame, ref, notes}, %{ref: ref} = state) do
    active =
      Enum.reduce(notes, state.active, fn note, active ->
        note_id = {note.channel, note.note}
        currently_active? = MapSet.member?(active, note_id)

        send_frame(note, currently_active?)

        active
        |> maybe_add_active(note_id, note.note_on)
        |> maybe_remove_active(note_id, note.note_off)
      end)

    {:noreply, %{state | active: active}}
  end

  # A stale frame from a performance we've already stopped/replaced - ignore.
  def handle_info({:frame, _ref, _notes}, state), do: {:noreply, state}

  def handle_info({:done, ref}, %{ref: ref} = state) do
    {:noreply, %{state | status: :stopped}}
  end

  def handle_info({:done, _ref}, state), do: {:noreply, state}

  defp send_frame(note, currently_active?) do
    if note.note_on do
      Connection.send_message(<<0x90 + note.channel, note.note, note.velocity>>)
    end

    if note.note_on or currently_active? do
      Connection.send_message(<<0xD0 + note.channel, note.pressure>>)

      bend = (8192 + note.bend * 8192) |> round() |> max(0) |> min(16_383)
      Connection.send_message(<<0xE0 + note.channel, rem(bend, 128), div(bend, 128)>>)

      Connection.send_message(<<0xB0 + note.channel, 74, note.slide>>)
    end

    if note.note_off do
      Connection.send_message(<<0x80 + note.channel, note.note, 0>>)
    end
  end

  defp maybe_add_active(active, note_id, true), do: MapSet.put(active, note_id)
  defp maybe_add_active(active, _note_id, false), do: active

  defp maybe_remove_active(active, note_id, true), do: MapSet.delete(active, note_id)
  defp maybe_remove_active(active, _note_id, false), do: active

  # Silences every currently-sounding note and invalidates any
  # already-scheduled frames from whatever was playing before (they'll
  # arrive tagged with the old `ref` and be ignored).
  defp stop_all(state) do
    Enum.each(state.active, fn {channel, note} ->
      Connection.send_message(<<0x80 + channel, note, 0>>)
    end)

    %{state | status: :stopped, ref: make_ref(), active: MapSet.new()}
  end
end
