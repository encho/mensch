defmodule Mensch.NotePlayer do
  @moduledoc """
  Represents a single sounding MIDI note on a dedicated MPE member
  channel.

  Osmose's EaganMatrix ignores Note On velocity and instead needs a
  continuous stream of Channel Pressure messages to produce and
  sustain any sound at all, so this GenServer keeps a timer running
  for as long as the note is held, sending Channel Pressure and a
  gentle Pitch Bend vibrato. Giving each note its own phase offset
  (see `:phase`) makes the modulation audibly independent per note -
  the essence of MPE, as opposed to legacy single-channel MIDI where
  pitch bend affects every note the same way.

  Pressure follows a classic attack/decay/sustain/release shape,
  self-scheduled at start from a `:milestones` map (absolute
  milliseconds since note-start - see `Mensch.Envelope.milestones/2`):
  attack ramps 0 -> `@peak_pressure`, decay ramps down to
  `@sustain_pressure`, sustain breathes gently around
  `@sustain_pressure` (exactly as before), and release ramps back down
  to 0, at which point the note stops itself (sending note-off). All
  three ramps are linear. Vibrato and the emphasis note's aftertouch
  push (see `slide_for/2`) are only active during sustain - they rest
  during attack/decay/release so a chord's onset and tail stay clean
  and predictable.

  If `milestones.total_ms` is `nil` (an indefinitely-held chord), the
  note never self-stops - it holds at sustain until `stop/1` is called
  explicitly, which (like any other explicit stop) is instant, with
  no release fade.

  Always sends note-off when stopped (whether stopped cooperatively or
  shut down by its parent `Mensch.ChordPlayer`), so a note can never
  get stuck sounding on the hardware.

  An optional `:start_delay_ms` (default `0`) defers the actual
  note-on and the start of this note's own envelope/tick loop by that
  many milliseconds - e.g. so a chord's notes can be staggered
  slightly (a "strum") rather than all starting in perfect unison.
  The process itself still starts (and can be stopped/linked)
  immediately; only the sounding of the note is delayed. If stopped
  before the delay elapses, no note-on/note-off is ever sent.
  """

  use GenServer

  @tick_ms 30
  @peak_pressure 127
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
  # zone), then releases back down before resting until the next
  # cycle. Named "aftertouch" (not "attack"/"release") to avoid
  # clashing with the note's own attack/decay/release envelope phases.
  @aftertouch_cycle_s 3.0
  @aftertouch_slide_rest 0
  @aftertouch_slide_peak 127
  @aftertouch_attack_s 0.2
  @aftertouch_hold_s 0.5
  @aftertouch_release_s 0.8

  defstruct [
    :number,
    :channel,
    :velocity,
    :phase,
    :started_at,
    :timer_ref,
    :milestones,
    emphasis: false,
    pressure: 0,
    bend: 0.0,
    slide: 0,
    started?: false
  ]

  # Client API

  @doc """
  Starts a note. `opts` must include `:number` (MIDI note number
  0-127), `:channel` (MPE member channel 0-15), and `:milestones` (a
  map from `Mensch.Envelope.milestones/2`); optionally `:velocity`
  (defaults to 100) and `:phase` (radians, defaults to 0) which offsets
  this note's vibrato/breathing from other simultaneously-sounding
  notes.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stops the note instantly, sending note-off before terminating."
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
      milestones: Keyword.fetch!(opts, :milestones),
      velocity: Keyword.get(opts, :velocity, 100),
      phase: Keyword.get(opts, :phase, 0.0),
      emphasis: Keyword.get(opts, :emphasis, false)
    }

    case Keyword.get(opts, :start_delay_ms, 0) do
      delay when delay > 0 ->
        Process.send_after(self(), :begin, delay)
        {:ok, state}

      _ ->
        {:ok, begin(state)}
    end
  end

  @impl true
  def handle_info(:begin, state) do
    {:noreply, begin(state)}
  end

  def handle_info(:tick, state) do
    elapsed_ms = System.monotonic_time(:millisecond) - state.started_at

    bend = bend_for(state, elapsed_ms)
    pressure = pressure_for(state, elapsed_ms)
    slide = slide_for(state, elapsed_ms)

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

  def handle_info(:envelope_elapsed, state) do
    {:stop, :normal, state}
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

    if state.started? do
      send_pitch_bend(state, 0.0)
      send_slide(state, @aftertouch_slide_rest)
      Mensch.Midi.Connection.send_message(<<0x80 + state.channel, state.number, 0>>)
    end

    :ok
  end

  # Sends note-on and starts this note's own envelope/tick loop, measuring
  # elapsed time from right now - i.e. from whenever the note actually
  # starts sounding, not from process start (which may have been earlier,
  # if :start_delay_ms staggered this note's onset).
  defp begin(state) do
    state = %{state | started_at: System.monotonic_time(:millisecond), started?: true}

    Mensch.Midi.Connection.send_message(<<0x90 + state.channel, state.number, state.velocity>>)

    initial_pressure = pressure_for(state, 0)
    send_channel_pressure(state, initial_pressure)
    send_slide(state, @aftertouch_slide_rest)

    if state.milestones.total_ms do
      Process.send_after(self(), :envelope_elapsed, state.milestones.total_ms)
    end

    %{
      state
      | timer_ref: schedule_tick(),
        pressure: initial_pressure,
        bend: 0.0,
        slide: @aftertouch_slide_rest
    }
  end

  # Attack: linear ramp up from silence to the envelope's peak.
  defp pressure_for(%{milestones: %{attack_end_ms: attack_end_ms}}, elapsed_ms)
       when elapsed_ms < attack_end_ms do
    lerp(0, @peak_pressure, safe_ratio(elapsed_ms, attack_end_ms))
  end

  # Decay: linear ramp down from peak to the sustain level.
  defp pressure_for(
         %{milestones: %{attack_end_ms: attack_end_ms, decay_end_ms: decay_end_ms}},
         elapsed_ms
       )
       when elapsed_ms < decay_end_ms do
    ratio = safe_ratio(elapsed_ms - attack_end_ms, decay_end_ms - attack_end_ms)
    lerp(@peak_pressure, @sustain_pressure, ratio)
  end

  # Release: linear ramp down from sustain to silence.
  defp pressure_for(
         %{milestones: %{release_start_ms: release_start_ms, total_ms: total_ms}},
         elapsed_ms
       )
       when not is_nil(release_start_ms) and elapsed_ms >= release_start_ms do
    lerp(
      @sustain_pressure,
      0,
      safe_ratio(elapsed_ms - release_start_ms, total_ms - release_start_ms)
    )
  end

  # Sustain: breathes gently and symmetrically around the sustain
  # level - confirmed by ear that pressure alone doesn't carry the
  # "aftertouch" character (see `slide_for/2` for what does).
  defp pressure_for(%{phase: phase}, elapsed_ms) do
    angle = 2 * :math.pi() * @pressure_rate_hz * (elapsed_ms / 1000) + phase
    @sustain_pressure + :math.sin(angle) * @pressure_depth
  end

  # Vibrato only during sustain - resting during attack/decay/release
  # keeps a chord's onset and tail clean and predictable.
  defp bend_for(state, elapsed_ms) do
    if in_sustain?(state, elapsed_ms) do
      angle = 2 * :math.pi() * @vibrato_rate_hz * (elapsed_ms / 1000) + state.phase
      :math.sin(angle) * @vibrato_depth
    else
      0.0
    end
  end

  # The emphasis note runs an attack/hold/release/rest envelope on CC74
  # (Slide) on its own dedicated cycle length, staggered per-note by
  # offsetting where in the cycle it starts (derived from :phase): a
  # push up into the top of the range - the distinct aftertouch zone -
  # held briefly, then released back down to rest. Only runs during
  # sustain, same as the vibrato.
  defp slide_for(%{emphasis: true, phase: phase} = state, elapsed_ms) do
    if in_sustain?(state, elapsed_ms) do
      elapsed_seconds = elapsed_ms / 1000
      offset = phase / (2 * :math.pi()) * @aftertouch_cycle_s
      t = :math.fmod(elapsed_seconds + offset, @aftertouch_cycle_s)
      range = @aftertouch_slide_peak - @aftertouch_slide_rest

      cond do
        t < @aftertouch_attack_s ->
          @aftertouch_slide_rest + t / @aftertouch_attack_s * range

        t < @aftertouch_attack_s + @aftertouch_hold_s ->
          @aftertouch_slide_peak

        t < @aftertouch_attack_s + @aftertouch_hold_s + @aftertouch_release_s ->
          release_t = t - (@aftertouch_attack_s + @aftertouch_hold_s)
          @aftertouch_slide_peak - release_t / @aftertouch_release_s * range

        true ->
          @aftertouch_slide_rest
      end
    else
      @aftertouch_slide_rest
    end
  end

  # Other notes just sit at rest - no Slide push.
  defp slide_for(_state, _elapsed_ms), do: @aftertouch_slide_rest

  defp in_sustain?(%{milestones: milestones}, elapsed_ms) do
    elapsed_ms >= milestones.decay_end_ms and
      (is_nil(milestones.release_start_ms) or elapsed_ms < milestones.release_start_ms)
  end

  defp lerp(from, to, ratio), do: from + (to - from) * ratio

  defp safe_ratio(_numerator, denominator) when denominator <= 0, do: 1.0
  defp safe_ratio(numerator, denominator), do: (numerator / denominator) |> max(0.0) |> min(1.0)

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
