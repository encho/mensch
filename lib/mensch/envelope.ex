defmodule Mensch.Envelope do
  @moduledoc """
  How a chord begins and ends: a classic attack/decay/sustain/release
  shape, expressed in musical time (bars) rather than raw
  milliseconds, so it stays correct regardless of tempo.

  Sustain has no field of its own - it's simply whatever's left of
  `:duration_bars` after attack, decay, and release. A `:duration_bars`
  of `0` means the chord holds indefinitely (no decay-to-sustain
  self-timing beyond attack/decay, and no self-scheduled release -
  see `milestones/2`); it keeps sounding until something explicitly
  stops it.

  Deliberately kept separate from `Mensch.Chord` (which is just pitch
  content) - the same chord can be played with different envelopes.
  """

  defstruct duration_bars: 4, attack_bars: 0.1, decay_bars: 0.1, release_bars: 0.25

  @type t :: %__MODULE__{
          duration_bars: number(),
          attack_bars: number(),
          decay_bars: number(),
          release_bars: number()
        }

  @doc """
  Converts this envelope's bar-lengths into a milestone map of
  absolute milliseconds since chord-start, using `timing` (a
  `Mensch.Timing{}` snapshot) to translate bars into ms:

    * `:attack_end_ms` - when attack gives way to decay
    * `:decay_end_ms` - when decay gives way to sustain
    * `:release_start_ms` - when sustain gives way to release, or
      `nil` if `:duration_bars` is `0` (indefinite hold)
    * `:total_ms` - when release finishes and the chord should stop
      itself, or `nil` for the same reason

  If attack + decay + release together would exceed the chord's
  total duration, all three are scaled down proportionally so they
  still fit (sustain never goes negative).
  """
  def milestones(%__MODULE__{duration_bars: duration_bars} = envelope, timing)
      when duration_bars <= 0 do
    attack_ms = Mensch.Timing.bars_to_ms(timing, envelope.attack_bars)
    decay_ms = Mensch.Timing.bars_to_ms(timing, envelope.decay_bars)

    %{
      attack_end_ms: attack_ms,
      decay_end_ms: attack_ms + decay_ms,
      release_start_ms: nil,
      total_ms: nil
    }
  end

  def milestones(%__MODULE__{} = envelope, timing) do
    total_ms = Mensch.Timing.bars_to_ms(timing, envelope.duration_bars)
    attack_ms = Mensch.Timing.bars_to_ms(timing, envelope.attack_bars)
    decay_ms = Mensch.Timing.bars_to_ms(timing, envelope.decay_bars)
    release_ms = Mensch.Timing.bars_to_ms(timing, envelope.release_bars)
    sum_ms = attack_ms + decay_ms + release_ms

    scale = if sum_ms > total_ms and sum_ms > 0, do: total_ms / sum_ms, else: 1.0

    attack_ms = round(attack_ms * scale)
    decay_ms = round(decay_ms * scale)
    release_ms = round(release_ms * scale)

    %{
      attack_end_ms: attack_ms,
      decay_end_ms: attack_ms + decay_ms,
      release_start_ms: total_ms - release_ms,
      total_ms: total_ms
    }
  end

  @doc """
  Rescales a milestones map (from `milestones/2`) so its `:total_ms`
  fits within `max_total_ms`, proportionally shrinking
  attack/decay/release to match if it would otherwise run over -
  e.g. so an individual note's own envelope never outlives the
  containing chord's overall envelope.

  A `nil` `max_total_ms`, or a `milestones` whose own `:total_ms` is
  already `nil` (an indefinite hold), means there's nothing to
  constrain against - `milestones` is returned unchanged. Likewise,
  if `milestones.total_ms` already fits within `max_total_ms`, it's
  returned unchanged.
  """
  def constrain(milestones, nil), do: milestones
  def constrain(%{total_ms: nil} = milestones, _max_total_ms), do: milestones

  def constrain(%{total_ms: total_ms} = milestones, max_total_ms) when total_ms <= max_total_ms do
    milestones
  end

  def constrain(%{total_ms: total_ms} = milestones, max_total_ms) do
    max_total_ms = max(max_total_ms, 0)
    scale = if total_ms > 0, do: max_total_ms / total_ms, else: 1.0

    %{
      attack_end_ms: round(milestones.attack_end_ms * scale),
      decay_end_ms: round(milestones.decay_end_ms * scale),
      release_start_ms: round(milestones.release_start_ms * scale),
      total_ms: max_total_ms
    }
  end
end
