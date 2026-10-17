defmodule Mensch.SampleDb.Sample7DynamicVoicing do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Machines.DynamicVoicing.NoteModulationStrategies.DynamicVoicingEnvelopedPressure
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.SampleDefinition
  alias Mensch.SampleEntry
  alias Mensch.TimelineContext

  @behaviour Mensch.SampleDefinition.Provider
  @spec sample(pos_integer()) :: SampleDefinition.t()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %SampleDefinition{
      id: "sample-7-dynamic-voicing",
      created_at: ~U[2026-01-01 00:00:00Z],
      folder: "Dynamic Voicing",
      name: "Bb Major Jazz Cycle (ii-V-I-vi)",
      total_length_bars: 4,
      sample_context:
        SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{
              type: :open,
              inversion_resolution_mode: :anchor_then_wander
            },
            root: :c,
            quality: :min7,
            octave: 2,
            inversion: 0
          },
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
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{
              type: :open,
              inversion_resolution_mode: :anchor_then_wander
            },
            root: :f,
            quality: :dom7,
            octave: 2,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :down,
              number_of_inversions: 8,
              modulation_strategy: %DynamicVoicingEnvelopedPressure{
                error_prefix: "dynamic_voicing",
                pressure_attack_mbeats: 50.0
              }
            }
          }
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{
              type: :open,
              inversion_resolution_mode: :anchor_then_wander
            },
            root: :b_flat,
            quality: :maj7,
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
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{
              type: :open,
              inversion_resolution_mode: :anchor_then_wander
            },
            root: :g,
            quality: :min7,
            octave: 2,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :down,
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
