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

  defstruct status: :stopped,
            ref: nil,
            active: MapSet.new(),
            pending_frames: [],
            next_timer_ref: nil,
            last_frame_at_ms: nil

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
    state = normalize_state(state)
    state = stop_all(state)
    ref = make_ref()
    frames = normalize_frames(data.frames)

    state =
      %{
        state
        | status: :playing,
          ref: ref,
          pending_frames: frames,
          next_timer_ref: nil,
          last_frame_at_ms: nil
      }
      |> schedule_next_dispatch()

    {:reply, :ok, state}
  end

  def handle_call(:stop, _from, state) do
    state = normalize_state(state)
    state = panic_all(state)
    schedule_panic_retries(state.ref)
    {:reply, :ok, state}
  end

  def handle_call(:panic, _from, state) do
    state = normalize_state(state)
    state = panic_all(state)
    schedule_panic_retries(state.ref)
    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    state = normalize_state(state)
    {:reply, state.status, state}
  end

  @impl true
  def handle_info(
        {:dispatch_frame, ref},
        %{ref: ref, status: :playing, pending_frames: [frame | rest]} = state
      ) do
    state = normalize_state(state)

    state =
      apply_frame(frame, state)
      |> Map.put(:pending_frames, rest)
      |> Map.put(:next_timer_ref, nil)
      |> Map.put(:last_frame_at_ms, frame.at_ms)

    case rest do
      [] ->
        {:noreply,
         %{
           state
           | status: :stopped,
             last_frame_at_ms: nil
         }}

      _ ->
        {:noreply, schedule_next_dispatch(state)}
    end
  end

  def handle_info({:dispatch_frame, _ref}, state), do: {:noreply, state}

  def handle_info({:panic_retry, ref, retries_left}, %{ref: ref} = state)
      when is_integer(retries_left) and retries_left > 0 do
    state = normalize_state(state)
    panic_burst(target_channels(state))
    Process.send_after(self(), {:panic_retry, ref, retries_left - 1}, 30)
    {:noreply, state}
  end

  def handle_info({:panic_retry, _ref, _retries_left}, state), do: {:noreply, state}

  defp apply_frame(frame, state) do
    active =
      Enum.reduce(frame.notes, state.active, fn note, active ->
        note_id = {note.channel, note.midi_note}

        send_frame(note)

        active
        |> maybe_add_active(note_id, note.note_on)
        |> maybe_remove_active(note_id, note.note_off)
      end)

    %{state | active: active}
  end

  defp send_frame(note) do
    messages =
      []
      |> maybe_append_modulation(note)
      |> maybe_append_note_on(note)
      |> maybe_append_note_off(note)

    Connection.send_messages(messages)
  end

  defp maybe_append_note_on(messages, %{note_on: true} = note) do
    messages ++ [<<0x90 + note.channel, note.midi_note, note.note_on_velocity>>]
  end

  defp maybe_append_note_on(messages, _note), do: messages

  defp maybe_append_modulation(messages, %{note_off: true}), do: messages

  defp maybe_append_modulation(messages, note) do
    bend = (8192 + note.bend * 8192) |> round() |> max(0) |> min(16_383)
    pressure = effective_pressure(note)

    messages ++
      [
        <<0xD0 + note.channel, pressure>>,
        <<0xE0 + note.channel, rem(bend, 128), div(bend, 128)>>,
        <<0xB0 + note.channel, 74, note.slide>>
      ]
  end

  defp maybe_append_note_off(messages, %{note_off: true} = note) do
    messages ++ [<<0x80 + note.channel, note.midi_note, 0>>]
  end

  defp maybe_append_note_off(messages, _note), do: messages

  defp maybe_add_active(active, note_id, true), do: MapSet.put(active, note_id)
  defp maybe_add_active(active, _note_id, false), do: active

  defp maybe_remove_active(active, note_id, true), do: MapSet.delete(active, note_id)
  defp maybe_remove_active(active, _note_id, false), do: active

  # Silences every currently-sounding note and invalidates any
  # already-scheduled frames from whatever was playing before (they'll
  # arrive tagged with the old `ref` and be ignored).
  defp stop_all(state) do
    cancel_timer(state.next_timer_ref)

    messages =
      Enum.flat_map(state.active, fn {channel, note} ->
        [
          <<0x80 + channel, note, 0>>,
          <<0x90 + channel, note, 0>>
        ]
      end)

    Connection.send_messages(messages)

    %{
      state
      | status: :stopped,
        ref: make_ref(),
        active: MapSet.new(),
        pending_frames: [],
        next_timer_ref: nil,
        last_frame_at_ms: nil
    }
  end

  defp panic_all(state) do
    cancel_timer(state.next_timer_ref)
    channels = target_channels(state)
    panic_burst(channels)

    %{
      state
      | status: :stopped,
        ref: make_ref(),
        active: MapSet.new(),
        pending_frames: [],
        next_timer_ref: nil,
        last_frame_at_ms: nil
    }
  end

  defp panic_burst(channels) do
    messages =
      Enum.flat_map(channels, fn channel ->
        controller_resets = [
          # Channel pressure zero prevents hanging expression after note-off.
          <<0xD0 + channel, 0>>,
          # Reset pitch bend to center.
          <<0xE0 + channel, 0, 64>>,
          # Reset timbre/slide controller.
          <<0xB0 + channel, 74, 0>>,
          # Sustain off.
          <<0xB0 + channel, 64, 0>>,
          # Reset all controllers.
          <<0xB0 + channel, 121, 0>>,
          # Panic CCs: all sound off + all notes off.
          <<0xB0 + channel, 120, 0>>,
          <<0xB0 + channel, 123, 0>>
        ]

        note_offs =
          Enum.flat_map(0..127, fn note ->
            [
              <<0x80 + channel, note, 0>>,
              <<0x90 + channel, note, 0>>
            ]
          end)

        controller_resets ++ note_offs
      end)

    Connection.send_messages(messages)
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

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer_ref) do
    _ = Process.cancel_timer(timer_ref)
    :ok
  end

  defp schedule_next_dispatch(
         %{status: :playing, ref: ref, pending_frames: [next_frame | _]} = state
       ) do
    delay_ms =
      case state.last_frame_at_ms do
        nil -> 0
        last_frame_at_ms -> max(next_frame.at_ms - last_frame_at_ms, 0)
      end

    next_timer_ref = Process.send_after(self(), {:dispatch_frame, ref}, delay_ms)
    %{state | next_timer_ref: next_timer_ref}
  end

  defp schedule_next_dispatch(state), do: state

  defp normalize_frames(frames) when is_list(frames) do
    Enum.sort_by(frames, & &1.at_ms)
  end

  defp normalize_frames(_frames), do: []

  # Some pressure-driven synths need a non-zero pressure value at note-on
  # time to reliably start sound.
  defp effective_pressure(%{note_on: true, pressure: pressure}) when pressure <= 0, do: 1
  defp effective_pressure(note), do: note.pressure

  # During hot code reload, an existing process may still hold an older
  # struct shape. Normalize to the current struct keys before updates.
  defp normalize_state(state) do
    state_map =
      cond do
        is_struct(state) ->
          Map.from_struct(state)

        is_map(state) ->
          Map.delete(state, :__struct__)

        true ->
          %{}
      end

    merged =
      %__MODULE__{}
      |> Map.from_struct()
      |> Map.merge(state_map)

    struct!(__MODULE__, merged)
  end
end
