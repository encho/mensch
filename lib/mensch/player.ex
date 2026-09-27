defmodule Mensch.Player do
  @moduledoc """
  Plays a precomputed performance (see `Mensch.PerformanceAssembler.generate_sample/0`) in
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
  `Mensch.PerformanceAssembler.generate_sample/0`) in real time,
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

  @doc "Force-silences all member channels (panic/all-notes-off)."
  def panic do
    GenServer.call(__MODULE__, :panic)
  end

  # Server callbacks

  @impl true
  def init(_opts), do: {:ok, %__MODULE__{}}

  @impl true
  def handle_call({:play, data}, _from, state) do
    state = stop_all(state)
    ref = make_ref()

    Enum.each(data.frames, fn frame ->
      Process.send_after(self(), {:frame, ref, frame.notes}, frame.at_ms)
    end)

    Process.send_after(self(), {:done, ref}, data.duration_ms + data.granularity_ms)

    {:reply, :ok, %{state | status: :playing, ref: ref}}
  end

  def handle_call(:stop, _from, state) do
    state = panic_all(state)
    schedule_panic_retries(state.ref)
    {:reply, :ok, state}
  end

  def handle_call(:panic, _from, state) do
    state = panic_all(state)
    schedule_panic_retries(state.ref)
    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({:frame, ref, notes}, %{ref: ref} = state) do
    active =
      Enum.reduce(notes, state.active, fn note, active ->
        note_id = {note.channel, note.midi_note}

        send_frame(note)

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

  def handle_info({:panic_retry, ref, retries_left}, %{ref: ref} = state)
      when is_integer(retries_left) and retries_left > 0 do
    panic_burst(target_channels(state))
    Process.send_after(self(), {:panic_retry, ref, retries_left - 1}, 30)
    {:noreply, state}
  end

  def handle_info({:panic_retry, _ref, _retries_left}, state), do: {:noreply, state}

  defp send_frame(note) do
    if note.note_on do
      Connection.send_message(<<0x90 + note.channel, note.midi_note, note.note_on_velocity>>)
    end

    if not note.note_off do
      Connection.send_message(<<0xD0 + note.channel, note.pressure>>)

      bend = (8192 + note.bend * 8192) |> round() |> max(0) |> min(16_383)
      Connection.send_message(<<0xE0 + note.channel, rem(bend, 128), div(bend, 128)>>)

      Connection.send_message(<<0xB0 + note.channel, 74, note.slide>>)
    end

    if note.note_off do
      Connection.send_message(<<0x80 + note.channel, note.midi_note, 0>>)
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

  defp panic_all(state) do
    channels = target_channels(state)
    panic_burst(channels)

    %{state | status: :stopped, ref: make_ref(), active: MapSet.new()}
  end

  defp panic_burst(channels) do
    Enum.each(channels, fn channel ->
      # Channel pressure zero prevents hanging expression after note-off.
      Connection.send_message(<<0xD0 + channel, 0>>)
      # Reset pitch bend to center.
      Connection.send_message(<<0xE0 + channel, 0, 64>>)
      # Reset timbre/slide controller.
      Connection.send_message(<<0xB0 + channel, 74, 0>>)
      # Sustain off.
      Connection.send_message(<<0xB0 + channel, 64, 0>>)
      # Reset all controllers.
      Connection.send_message(<<0xB0 + channel, 121, 0>>)
      # Panic CCs: all sound off + all notes off.
      Connection.send_message(<<0xB0 + channel, 120, 0>>)
      Connection.send_message(<<0xB0 + channel, 123, 0>>)

      Enum.each(0..127, fn note ->
        Connection.send_message(<<0x80 + channel, note, 0>>)
      end)
    end)
  end

  defp schedule_panic_retries(ref) do
    Process.send_after(self(), {:panic_retry, ref, 2}, 30)
  end

  defp target_channels(state) do
    active_channels =
      state.active
      |> Enum.map(fn {channel, _note} -> channel end)
      |> MapSet.new()

    target_channels =
      0..15
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Connection.member_channels()))
      |> MapSet.union(active_channels)

    MapSet.to_list(target_channels)
  end
end
