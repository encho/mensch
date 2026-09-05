defmodule Mensch.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Mensch.Envelope
  alias Mensch.Timing

  defp timing(bpm) do
    %Timing{bpm: bpm, beats_per_bar: 4, started_at: 0}
  end

  describe "milestones/2" do
    test "converts bars to ms milestones at a given tempo" do
      # 120 bpm -> 500ms/beat -> 2000ms/bar
      envelope = %Envelope{
        duration_bars: 4,
        attack_bars: 0.25,
        decay_bars: 0.25,
        release_bars: 0.5
      }

      milestones = Envelope.milestones(envelope, timing(120))

      assert milestones.attack_end_ms == 500
      assert milestones.decay_end_ms == 1000
      assert milestones.release_start_ms == 7000
      assert milestones.total_ms == 8000
    end

    test "proportionally scales down attack/decay/release if they exceed the total duration" do
      envelope = %Envelope{duration_bars: 1, attack_bars: 1, decay_bars: 1, release_bars: 2}
      milestones = Envelope.milestones(envelope, timing(120))

      # total is 2000ms, but attack+decay+release bars sum to 4 bars (8000ms) -
      # scaled down by 0.25 so they exactly fit within the 2000ms total.
      assert milestones.total_ms == 2000
      assert milestones.attack_end_ms == 500
      assert milestones.decay_end_ms == 1000
      assert milestones.release_start_ms == 1000
    end

    test "duration_bars of 0 means indefinite hold: no release_start_ms/total_ms" do
      envelope = %Envelope{
        duration_bars: 0,
        attack_bars: 0.25,
        decay_bars: 0.25,
        release_bars: 0.5
      }

      milestones = Envelope.milestones(envelope, timing(120))

      assert milestones.attack_end_ms == 500
      assert milestones.decay_end_ms == 1000
      assert milestones.release_start_ms == nil
      assert milestones.total_ms == nil
    end

    test "zero-length attack/decay/release still yields a valid (all-sustain) envelope" do
      envelope = %Envelope{duration_bars: 4, attack_bars: 0, decay_bars: 0, release_bars: 0}
      milestones = Envelope.milestones(envelope, timing(120))

      assert milestones.attack_end_ms == 0
      assert milestones.decay_end_ms == 0
      assert milestones.release_start_ms == 8000
      assert milestones.total_ms == 8000
    end
  end
end
