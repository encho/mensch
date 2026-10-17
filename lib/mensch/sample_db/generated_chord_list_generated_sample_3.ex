defmodule Mensch.SampleDb.GeneratedChordListGeneratedSample3 do
  @moduledoc false

  alias Mensch.SampleContext
  alias Mensch.SampleDefinition

  @behaviour Mensch.SampleDefinition.Provider

  @spec sample(pos_integer()) :: SampleDefinition.t()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %SampleDefinition{
      id: "chord_list_generated_sample-3",
      created_at: ~U[2026-01-01 00:00:00Z],
      folder: "Generated",
      name: "Chord List Generated Sample",
      total_length_mbeats: 12000,
      blueprint_meta: %{
        bpm: 120,
        time_signature: {4, 4},
        frame_mbeats: 50,
        chord_duration_mbeats: 4000,
        silence_after_chord_mbeats: 0,
        blueprint_additional_params: %{
          "direction_mode" => "alternate",
          "number_of_inversions" => 8,
          "pressure_attack_mbeats" => 50.0
        },
        blueprint_id: "progression__alternating_wander__dv1"
      },
      sample_context:
        SampleContext.new!(%{
          bpm: 120,
          time_signature: {4, 4},
          frame_mbeats: frame_mbeats
        }),
      sample_entries: [
        %Mensch.SampleEntry{
          chord_spec: %Mensch.Harmony.ChordSpec{
            root: :c,
            tones: nil,
            quality: :maj7,
            octave: 3,
            inversion: 0,
            voicing: %Mensch.Harmony.ChordSpec.Voicing{
              type: :close,
              center_note: 60,
              range_min: nil,
              range_max: nil,
              voice_count: nil,
              doubling: :auto,
              inversion_resolution_mode: :anchor_then_wander
            },
            min_voice_count: 4,
            foreign_bass: nil
          },
          timeline_context: %Mensch.TimelineContext{
            start_beat: %Mensch.BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %Mensch.Machines.DynamicVoicing{
            params: %Mensch.Machines.DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 8,
              modulation_strategy:
                %Mensch.Machines.DynamicVoicing.NoteModulationStrategies.DynamicVoicingEnvelopedPressure{
                  pressure_attack_mbeats: 50.0,
                  pressure_decay_mbeats: 280.0,
                  pressure_release_mbeats: 120.0,
                  pressure_sustain_level: 0.68,
                  pressure_curve: :sine,
                  pressure_curve_min: 0.0,
                  pressure_curve_max: 0.0,
                  pressure_curve_cycles_per_bar: 10.0,
                  pressure_curve_shift_mbeats: 0.0,
                  pressure_curve_anchor: :sample,
                  pressure_mode: :add,
                  error_prefix: "dynamic_voicing"
                }
            }
          }
        },
        %Mensch.SampleEntry{
          chord_spec: %Mensch.Harmony.ChordSpec{
            root: :c,
            tones: nil,
            quality: :min7_add11,
            octave: 3,
            inversion: 0,
            voicing: %Mensch.Harmony.ChordSpec.Voicing{
              type: :close,
              center_note: 60,
              range_min: nil,
              range_max: nil,
              voice_count: nil,
              doubling: :auto,
              inversion_resolution_mode: :anchor_then_wander
            },
            min_voice_count: 5,
            foreign_bass: nil
          },
          timeline_context: %Mensch.TimelineContext{
            start_beat: %Mensch.BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %Mensch.Machines.DynamicVoicing{
            params: %Mensch.Machines.DynamicVoicingParams{
              direction: :down,
              number_of_inversions: 8,
              modulation_strategy:
                %Mensch.Machines.DynamicVoicing.NoteModulationStrategies.DynamicVoicingEnvelopedPressure{
                  pressure_attack_mbeats: 50.0,
                  pressure_decay_mbeats: 280.0,
                  pressure_release_mbeats: 120.0,
                  pressure_sustain_level: 0.68,
                  pressure_curve: :sine,
                  pressure_curve_min: 0.0,
                  pressure_curve_max: 0.0,
                  pressure_curve_cycles_per_bar: 10.0,
                  pressure_curve_shift_mbeats: 0.0,
                  pressure_curve_anchor: :sample,
                  pressure_mode: :add,
                  error_prefix: "dynamic_voicing"
                }
            }
          }
        },
        %Mensch.SampleEntry{
          chord_spec: %Mensch.Harmony.ChordSpec{
            root: :e_flat,
            tones: nil,
            quality: :maj7,
            octave: 3,
            inversion: 0,
            voicing: %Mensch.Harmony.ChordSpec.Voicing{
              type: :close,
              center_note: 60,
              range_min: nil,
              range_max: nil,
              voice_count: nil,
              doubling: :auto,
              inversion_resolution_mode: :anchor_then_wander
            },
            min_voice_count: 4,
            foreign_bass: nil
          },
          timeline_context: %Mensch.TimelineContext{
            start_beat: %Mensch.BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %Mensch.Machines.DynamicVoicing{
            params: %Mensch.Machines.DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 8,
              modulation_strategy:
                %Mensch.Machines.DynamicVoicing.NoteModulationStrategies.DynamicVoicingEnvelopedPressure{
                  pressure_attack_mbeats: 50.0,
                  pressure_decay_mbeats: 280.0,
                  pressure_release_mbeats: 120.0,
                  pressure_sustain_level: 0.68,
                  pressure_curve: :sine,
                  pressure_curve_min: 0.0,
                  pressure_curve_max: 0.0,
                  pressure_curve_cycles_per_bar: 10.0,
                  pressure_curve_shift_mbeats: 0.0,
                  pressure_curve_anchor: :sample,
                  pressure_mode: :add,
                  error_prefix: "dynamic_voicing"
                }
            }
          }
        }
      ]
    }
  end
end
