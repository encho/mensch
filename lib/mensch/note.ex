defmodule Mensch.Note do
  @moduledoc """
  Represents a single sounding MIDI note on a dedicated MPE member
  channel.

  Osmose's EaganMatrix ignores Note On velocity and instead needs a
  continuous stream of Channel Pressure messages to produce and sustain
  any sound at all, so this GenServer keeps a timer running for as long
  as the note is held, sending Channel Pressure (held near a sustain
  level) and a gentle Pitch Bend vibrato. Giving each note its own
  phase offset (see `:phase`) makes the modulation audibly independent
  per note - the essence of MPE, as opposed to legacy single-channel
  MIDI where pitch bend affects every note the same way.

  Always sends note-off when stopped (whether stopped cooperatively or
  shut down by its parent `Mensch.Chord`), so a note can never get
  stuck sounding on the hardware.
  """

  use GenServer

  @tick_ms 30
  @sustain_pressure 100
  @vibrato_rate_hz 5.0
  @vibrato_depth 0.03

  defstruct [:number, :channel, :velocity, :phase, :started_at, :timer_ref]

  # Client API

  @doc """
  Starts a note. `opts` must include `:number` (MIDI note number 0-127)
  and `:channel` (MPE member channel 0-15); optionally `:velocity`
  (defaults to 100) and `:phase` (radians, defaults to 0) which offsets
  this note's vibrato from other simultaneously-sounding notes.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stops the note, sending note-off before terminating."
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      number: Keyword.fetch!(opts, :number),
      channel: Keyword.fetch!(opts, :channel),
      velocity: Keyword.get(opts, :velocity, 100),
      phase: Keyword.get(opts, :phase, 0.0),
      started_at: System.monotonic_time(:millisecond)
    }

    Mensch.Midi.Connection.send_message(<<0x90 + state.channel, state.number, state.velocity>>)
    send_channel_pressure(state, @sustain_pressure)

    {:ok, %{state | timer_ref: schedule_tick()}}
  end

  @impl true
  def handle_info(:tick, state) do
    elapsed_seconds = (System.monotonic_time(:millisecond) - state.started_at) / 1000
    angle = 2 * :math.pi() * @vibrato_rate_hz * elapsed_seconds + state.phase

    send_pitch_bend(state, :math.sin(angle) * @vibrato_depth)
    send_channel_pressure(state, @sustain_pressure)

    {:noreply, %{state | timer_ref: schedule_tick()}}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    send_pitch_bend(state, 0.0)
    Mensch.Midi.Connection.send_message(<<0x80 + state.channel, state.number, 0>>)
    :ok
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)

  defp send_channel_pressure(state, value) do
    Mensch.Midi.Connection.send_message(<<0xD0 + state.channel, clamp_7bit(value)>>)
  end

  defp send_pitch_bend(state, ratio) do
    bend = (8192 + ratio * 8192) |> round() |> max(0) |> min(16_383)
    Mensch.Midi.Connection.send_message(<<0xE0 + state.channel, rem(bend, 128), div(bend, 128)>>)
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end
