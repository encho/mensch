defmodule Mensch.SampleDb.Sample9DynamicVoicingCMajor do
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
    %{
      id: "sample-9-dynamic-voicing-c-major",
      folder: "Dynamic Voicing",
      name: "C Major Jazz Cycle (ii-V-I-vi)",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 10,
              lfo_slide: %LfoParams{
                curve: :sine,
                scale: 0.1,
                cycles_per_bar: 2.0,
                shift_mbeats: 0.0,
                polarity: :unipolar,
                time_base: :absolute,
                mode: :additive
              }
              # lfo_pressure: %LfoParams{
              #   curve: :sine,
              #   scale: 0.25,
              #   cycles_per_bar: 10.0,
              #   shift_mbeats: 0.0,
              #   time_base: :absolute,
              #   mode: :additive
              # }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 10,
              lfo_slide: %LfoParams{
                curve: :sine,
                scale: 0.1,
                cycles_per_bar: 2.0,
                shift_mbeats: 0.0,
                polarity: :unipolar,
                time_base: :absolute,
                mode: :additive
              },
              lfo_pressure: %LfoParams{
                curve: :sine,
                scale: 0.25,
                cycles_per_bar: 10.0,
                shift_mbeats: 0.0,
                time_base: :absolute,
                mode: :additive
              }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 10,
              lfo_slide: %LfoParams{
                curve: :sine,
                scale: 0.1,
                cycles_per_bar: 2.0,
                shift_mbeats: 0.0,
                polarity: :unipolar,
                time_base: :absolute,
                mode: :additive
              },
              lfo_pressure: %LfoParams{
                curve: :sine,
                scale: 0.25,
                cycles_per_bar: 10.0,
                shift_mbeats: 0.0,
                time_base: :absolute,
                mode: :additive
              }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :a, modifier: :min7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 10,
              lfo_slide: %LfoParams{
                curve: :sine,
                scale: 0.1,
                cycles_per_bar: 2.0,
                shift_mbeats: 0.0,
                polarity: :unipolar,
                time_base: :absolute,
                mode: :additive
              },
              lfo_pressure: %LfoParams{
                curve: :sine,
                scale: 0.25,
                cycles_per_bar: 10.0,
                shift_mbeats: 0.0,
                time_base: :absolute,
                mode: :additive
              }
            }
          }
        }
      ]
    }
  end
end
