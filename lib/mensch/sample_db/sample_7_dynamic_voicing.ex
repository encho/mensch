defmodule Mensch.SampleDb.Sample7DynamicVoicing do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.DynamicVoicing.NoteModulationStrategies.DynamicVoicingEnvelopedPressure
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %{
      id: "sample-7-dynamic-voicing",
      folder: "Dynamic Voicing",
      name: "Bb Major Jazz Cycle (ii-V-I-vi)",
      total_length_bars: 4,
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, tones: ["1", "b3", "5", "b7"], octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 8,
              modulation_strategy: %DynamicVoicingEnvelopedPressure{
                error_prefix: "dynamic_voicing",
                pressure_attack_mbeats: 50.0
              }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :f, tones: ["1", "3", "5", "b7"], octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 8,
              modulation_strategy: %DynamicVoicingEnvelopedPressure{
                error_prefix: "dynamic_voicing",
                pressure_attack_mbeats: 50.0
              }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{
            root: :a_sharp,
            tones: ["1", "3", "5", "7"],
            octave: 2,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 8,
              modulation_strategy: %DynamicVoicingEnvelopedPressure{
                error_prefix: "dynamic_voicing",
                pressure_attack_mbeats: 50.0
              }
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :g, tones: ["1", "b3", "5", "b7"], octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 8,
              modulation_strategy: %DynamicVoicingEnvelopedPressure{
                error_prefix: "dynamic_voicing",
                pressure_attack_mbeats: 50.0
              }
            }
          }
        }
      ]
    }
  end
end
