defmodule Mensch.SampleDb.Sample8DynamicVoicingOneBar do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.LfoParams
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @lfo_slide %LfoParams{
    curve: :sine,
    scale: 1,
    cycles_per_bar: 6.0,
    shift_mbeats: 0.0,
    polarity: :unipolar,
    time_base: :note,
    mode: :additive
  }

  @lfo_bend %LfoParams{
    curve: :sine,
    scale: 0.001,
    cycles_per_bar: 3.0,
    shift_mbeats: 0.0,
    polarity: :bipolar,
    time_base: :note,
    mode: :additive
  }

  @lfo_pressure %LfoParams{
    curve: :sine,
    scale: 5,
    cycles_per_bar: 10.0,
    shift_mbeats: 0.0,
    time_base: :sample,
    mode: :additive
  }

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: :up,
          number_of_inversions: 4,
          lfo_slide: @lfo_slide,
          lfo_bend: @lfo_bend,
          lfo_pressure: @lfo_pressure
        }
      }

    %{
      id: "sample-8-dynamic-voicing-one-bar",
      folder: "Dynamic Voicing",
      name: "Bbmaj7 · One Bar",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :a_sharp, modifier: :maj7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: machine
        }
      ]
    }
  end
end
