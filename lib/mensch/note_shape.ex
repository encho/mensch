defmodule Mensch.NoteShape do
  @moduledoc """
  Pure attack/decay/sustain/release pressure, vibrato pitch-bend, and
  aftertouch-slide shaping for a single sounding MPE note - a function
  of elapsed time since the note started, its `milestones` map
  (`:attack_end_ms`, `:decay_end_ms`, `:release_start_ms`,
  `:total_ms` - absolute milliseconds since note-start), its
  vibrato/breathing `phase` offset (radians), and whether it's the
  chord's `emphasis` (aftertouch) note.

  Used by `Mensch.PerformanceAssembler` to sample a note's whole life ahead of time,
  building a precomputed performance dataset.
  """

  alias Mensch.Envelope.ADSR

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
  @pressure_rate_hz 0.6
  @pressure_depth 12
  # The emphasis note's aftertouch push: CC74 (Slide) ramps from rest
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

  @doc "Which envelope phase `elapsed_ticks` falls into for the given ADSR envelope."
  def phase_at(%ADSR{} = adsr, elapsed_ticks) do
    ADSR.phase_at_tick(adsr, elapsed_ticks)
  end

  @doc "Channel Pressure (0-127, unclamped) at `elapsed_ticks`."
  def pressure(%ADSR{} = adsr, phase, elapsed_ticks, elapsed_ms) do
    base = ADSR.level_at_tick(adsr, elapsed_ticks) * @peak_pressure

    # Sustain breathes gently around the ADSR sustain level so note
    # body stays alive without changing attack/decay/release semantics.
    if ADSR.in_sustain_tick?(adsr, elapsed_ticks) do
      sustain_center = adsr.sustain_level * @peak_pressure
      base_offset = base - sustain_center

      angle = 2 * :math.pi() * @pressure_rate_hz * (elapsed_ms / 1000) + phase
      sustain_center + base_offset + :math.sin(angle) * @pressure_depth
    else
      base
    end
  end

  # Backward-compatible fallback for map-based milestone envelopes.
  def pressure(_milestones, phase, _elapsed_ticks, elapsed_ms) do
    angle = 2 * :math.pi() * @pressure_rate_hz * (elapsed_ms / 1000) + phase
    @sustain_pressure + :math.sin(angle) * @pressure_depth
  end

  @doc "Pitch bend ratio (-1.0..1.0, unclamped) at `elapsed_ms` - vibrato only during sustain."
  def bend(%ADSR{} = adsr, phase, elapsed_ms, elapsed_ticks) do
    if ADSR.in_sustain_tick?(adsr, elapsed_ticks) do
      angle = 2 * :math.pi() * @vibrato_rate_hz * (elapsed_ms / 1000) + phase
      :math.sin(angle) * @vibrato_depth
    else
      0.0
    end
  end

  @doc """
  CC74 Slide (0-127, unclamped) at `elapsed_ms` - only the `emphasis`
  note runs an attack/hold/release/rest cycle on its own dedicated
  cycle length (staggered per-note by offsetting where in the cycle
  it starts, derived from `phase`), and only during sustain, same as
  vibrato. Every other note just sits at rest.
  """
  def slide(%ADSR{} = adsr, phase, true = _emphasis, elapsed_ms, elapsed_ticks) do
    if ADSR.in_sustain_tick?(adsr, elapsed_ticks) do
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

  def slide(%ADSR{}, _phase, _emphasis, _elapsed_ms, _elapsed_ticks), do: @aftertouch_slide_rest

  @doc "Whether `elapsed_ticks` falls within the sustain phase of `adsr`."
  def in_sustain?(%ADSR{} = adsr, elapsed_ticks) do
    ADSR.in_sustain_tick?(adsr, elapsed_ticks)
  end
end
