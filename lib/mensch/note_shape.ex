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

  @doc "Which envelope phase `elapsed_ms` falls into, given `milestones`."
  def phase_at(milestones, elapsed_ms) do
    cond do
      elapsed_ms < milestones.attack_end_ms ->
        :attack

      elapsed_ms < milestones.decay_end_ms ->
        :decay

      not is_nil(milestones.release_start_ms) and elapsed_ms >= milestones.release_start_ms ->
        :release

      true ->
        :sustain
    end
  end

  @doc "Channel Pressure (0-127, unclamped) at `elapsed_ms`."
  # Attack: linear ramp up from silence to the envelope's peak.
  def pressure(%{attack_end_ms: attack_end_ms}, _phase, elapsed_ms)
      when elapsed_ms < attack_end_ms do
    lerp(0, @peak_pressure, safe_ratio(elapsed_ms, attack_end_ms))
  end

  # Decay: linear ramp down from peak to the sustain level.
  def pressure(%{attack_end_ms: attack_end_ms, decay_end_ms: decay_end_ms}, _phase, elapsed_ms)
      when elapsed_ms < decay_end_ms do
    ratio = safe_ratio(elapsed_ms - attack_end_ms, decay_end_ms - attack_end_ms)
    lerp(@peak_pressure, @sustain_pressure, ratio)
  end

  # Release: linear ramp down from sustain to silence.
  def pressure(%{release_start_ms: release_start_ms, total_ms: total_ms}, _phase, elapsed_ms)
      when not is_nil(release_start_ms) and elapsed_ms >= release_start_ms do
    lerp(
      @sustain_pressure,
      0,
      safe_ratio(elapsed_ms - release_start_ms, total_ms - release_start_ms)
    )
  end

  # Sustain: breathes gently and symmetrically around the sustain
  # level - confirmed by ear that pressure alone doesn't carry the
  # "aftertouch" character (see `slide/4` for what does).
  def pressure(_milestones, phase, elapsed_ms) do
    angle = 2 * :math.pi() * @pressure_rate_hz * (elapsed_ms / 1000) + phase
    @sustain_pressure + :math.sin(angle) * @pressure_depth
  end

  @doc "Pitch bend ratio (-1.0..1.0, unclamped) at `elapsed_ms` - vibrato only during sustain."
  def bend(milestones, phase, elapsed_ms) do
    if in_sustain?(milestones, elapsed_ms) do
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
  def slide(milestones, phase, true = _emphasis, elapsed_ms) do
    if in_sustain?(milestones, elapsed_ms) do
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

  def slide(_milestones, _phase, _emphasis, _elapsed_ms), do: @aftertouch_slide_rest

  @doc "Whether `elapsed_ms` falls within the sustain phase of `milestones`."
  def in_sustain?(milestones, elapsed_ms) do
    elapsed_ms >= milestones.decay_end_ms and
      (is_nil(milestones.release_start_ms) or elapsed_ms < milestones.release_start_ms)
  end

  defp lerp(from, to, ratio), do: from + (to - from) * ratio

  defp safe_ratio(_numerator, denominator) when denominator <= 0, do: 1.0
  defp safe_ratio(numerator, denominator), do: (numerator / denominator) |> max(0.0) |> min(1.0)
end
