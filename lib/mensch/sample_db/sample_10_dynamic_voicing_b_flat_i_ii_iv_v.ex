defmodule Mensch.SampleDb.Sample10DynamicVoicingBFlatIIiivv do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.LfoParams
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    frame_mbeats = 20

    %{
      id: "sample-10-dynamic-voicing-bb-i-ii-iv-v",
      folder: "Dynamic Voicing",
      name: "Bb Major (I-ii-IV-V) · cycle_up 2",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :a_sharp, modifier: :maj7, octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: {:cycle_up, 2},
              number_of_inversions: 4,
              lfo_pressure: %LfoParams{
                curve: :sine,
                scale: 0.25,
                cycles_per_bar: 20.0,
                shift_mbeats: 0.0,
                time_base: :sample,
                mode: :additive
              }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :min7, octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: {:cycle_up, 2},
              number_of_inversions: 4,
              lfo_pressure: %LfoParams{
                curve: :sine,
                scale: 0.25,
                cycles_per_bar: 20.0,
                shift_mbeats: 0.0,
                time_base: :sample,
                mode: :additive
              }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :d_sharp, modifier: :maj7, octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: {:cycle_up, 2},
              number_of_inversions: 4,
              lfo_pressure: %LfoParams{
                curve: :sine,
                scale: 0.25,
                cycles_per_bar: 20.0,
                shift_mbeats: 0.0,
                time_base: :sample,
                mode: :additive
              }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :f, modifier: :dom7, octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: {:cycle_up, 2},
              number_of_inversions: 4,
              lfo_pressure: %LfoParams{
                curve: :sine,
                scale: 0.25,
                cycles_per_bar: 20.0,
                shift_mbeats: 0.0,
                time_base: :sample,
                mode: :additive
              }
            }
          }
        }
      ]
    }
  end
end
