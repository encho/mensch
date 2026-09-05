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

  Confirmed by ear against the real hardware: raising Channel Pressure
  alone doesn't produce a distinctly different "aftertouch" character -
  it's CC74 (MPE's "Slide"/third-dimension parameter, Osmose's Y axis)
  that does. So the `:emphasis` note additionally runs a Slide push
  (see `slide_for/2`) up into that territory, while Channel Pressure
  just breathes gently like every other note.

  Always sends note-off when stopped (whether stopped cooperatively or
  shut down by its parent `Mensch.Chord`), so a note can never get
  stuck sounding on the hardware.
  """

  use GenServer

  @tick_ms 30
  @sustain_pressure 100
  @vibrato_rate_hz 4.0
  # Fraction of the full 14-bit pitch bend range. Kept tiny on purpose:
  # assuming Osmose's typical +/-48 semitone MPE bend range, this is
  # roughly +/-2 cents - just enough per-note drift to prove the
  # modulation is independent per note, without detuning the chord.
  @vibrato_depth 0.0004
  # Slow "breathing" pressure LFO, deliberately a different rate from
  # the vibrato so a note's pressure and pitch don't swell in lockstep.
  # Combined with each note's own :phase offset, notes breathe at
  # different points in their cycle rather than all pulsing together.
  @pressure_rate_hz 0.6
  @pressure_depth 12
  # The :emphasis note's aftertouch push: CC74 (Slide) ramps from rest
  # up to the top of the range, holds there (the distinct aftertouch
  # zone), then releases back down before resting until the next cycle.
  @emphasis_cycle_s 3.0
  @emphasis_slide_rest 0
  @emphasis_slide_peak 127
  @emphasis_attack_s 0.2
  @emphasis_hold_s 0.5
  @emphasis_release_s 0.8

  defstruct [
    :number,
    :channel,
    :velocity,
    :phase,
    :started_at,
    :timer_ref,
    emphasis: false,
    pressure: 0,
    bend: 0.0,
    slide: 0
  ]

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

  @doc "Returns the note's current `%{number:, channel:, pressure:, bend:, slide:}`."
  def snapshot(pid) do
    GenServer.call(pid, :snapshot)
  catch
    :exit, _ -> nil
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
      emphasis: Keyword.get(opts, :emphasis, false),
      started_at: System.monotonic_time(:millisecond)
    }

    Mensch.Midi.Connection.send_message(<<0x90 + state.channel, state.number, state.velocity>>)
    send_channel_pressure(state, @sustain_pressure)
    send_slide(state, @emphasis_slide_rest)

    {:ok,
     %{
       state
       | timer_ref: schedule_tick(),
         pressure: @sustain_pressure,
         bend: 0.0,
         slide: @emphasis_slide_rest
     }}
  end

  @impl true
  def handle_info(:tick, state) do
    elapsed_seconds = (System.monotonic_time(:millisecond) - state.started_at) / 1000
    bend_angle = 2 * :math.pi() * @vibrato_rate_hz * elapsed_seconds + state.phase

    bend = :math.sin(bend_angle) * @vibrato_depth
    pressure = pressure_for(state, elapsed_seconds)
    slide = slide_for(state, elapsed_seconds)

    send_pitch_bend(state, bend)
    send_channel_pressure(state, pressure)
    send_slide(state, slide)

    {:noreply,
     %{
       state
       | timer_ref: schedule_tick(),
         pressure: clamp_7bit(pressure),
         bend: bend,
         slide: clamp_7bit(slide)
     }}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      number: state.number,
      channel: state.channel,
      pressure: state.pressure,
      bend: state.bend,
      slide: state.slide,
      emphasis: state.emphasis
    }

    {:reply, snapshot, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    send_pitch_bend(state, 0.0)
    send_slide(state, @emphasis_slide_rest)
    Mensch.Midi.Connection.send_message(<<0x80 + state.channel, state.number, 0>>)
    :ok
  end

  # Every note just breathes gently and symmetrically around the
  # sustain level - confirmed by ear that pressure alone doesn't carry
  # the "aftertouch" character (see `slide_for/2` for what does).
  defp pressure_for(%{phase: phase}, elapsed_seconds) do
    angle = 2 * :math.pi() * @pressure_rate_hz * elapsed_seconds + phase
    @sustain_pressure + :math.sin(angle) * @pressure_depth
  end

  # The emphasis note runs an attack/hold/release/rest envelope on CC74
  # (Slide) on its own dedicated cycle length, staggered per-note by
  # offsetting where in the cycle it starts (derived from :phase): a
  # push up into the top of the range - the distinct aftertouch zone -
  # held briefly, then released back down to rest.
  defp slide_for(%{emphasis: true, phase: phase}, elapsed_seconds) do
    offset = phase / (2 * :math.pi()) * @emphasis_cycle_s
    t = :math.fmod(elapsed_seconds + offset, @emphasis_cycle_s)
    range = @emphasis_slide_peak - @emphasis_slide_rest

    cond do
      t < @emphasis_attack_s ->
        @emphasis_slide_rest + t / @emphasis_attack_s * range

      t < @emphasis_attack_s + @emphasis_hold_s ->
        @emphasis_slide_peak

      t < @emphasis_attack_s + @emphasis_hold_s + @emphasis_release_s ->
        release_t = t - (@emphasis_attack_s + @emphasis_hold_s)
        @emphasis_slide_peak - release_t / @emphasis_release_s * range

      true ->
        @emphasis_slide_rest
    end
  end

  # Other notes just sit at rest - no Slide push.
  defp slide_for(_state, _elapsed_seconds), do: @emphasis_slide_rest

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)

  defp send_channel_pressure(state, value) do
    Mensch.Midi.Connection.send_message(<<0xD0 + state.channel, clamp_7bit(value)>>)
  end

  defp send_slide(state, value) do
    Mensch.Midi.Connection.send_message(<<0xB0 + state.channel, 74, clamp_7bit(value)>>)
  end

  defp send_pitch_bend(state, ratio) do
    bend = (8192 + ratio * 8192) |> round() |> max(0) |> min(16_383)
    Mensch.Midi.Connection.send_message(<<0xE0 + state.channel, rem(bend, 128), div(bend, 128)>>)
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end
