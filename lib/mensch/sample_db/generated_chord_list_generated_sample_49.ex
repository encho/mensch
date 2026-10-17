defmodule Mensch.SampleDb.GeneratedChordListGeneratedSample49 do
  @moduledoc false

  alias Mensch.SampleContext
  alias Mensch.SampleDefinition

  @behaviour Mensch.SampleDefinition.Provider

  @spec sample(pos_integer()) :: SampleDefinition.t()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %SampleDefinition{
      id: "chord_list_generated_sample-49",
      created_at: ~U[2026-10-17 15:56:40Z],
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
    "pressure_attack_mbeats" => 50.0,
    "pressure_curve" => "triangle",
    "velocity" => 100
  },
  blueprint_id: "progression__steady_strum__strum1"
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
            root: :d,
            tones: nil,
            quality: :min7,
            octave: 3,
            inversion: 0,
            voicing: %Mensch.Harmony.ChordSpec.Voicing{
              type: :close,
              center_note: 47,
              range_min: 21,
              range_max: 108,
              voice_count: nil,
              doubling: :auto,
              inversion_resolution_mode: :per_step_centered
            },
            min_voice_count: 4,
            foreign_bass: nil
          },
          timeline_context: %Mensch.TimelineContext{
            start_beat: %Mensch.BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %Mensch.Machines.Strum{
            params: %Mensch.Machines.StrumParams{
              velocity: 100,
              modulation_strategy: %Mensch.Machines.Strum.NoteModulationStrategies.StrumEnvelopedPressure{
                pressure_attack_mbeats: 50.0,
                pressure_decay_mbeats: 280.0,
                pressure_release_mbeats: 120.0,
                pressure_sustain_level: 0.68,
                slide_peak_value: 125.0,
                pressure_curve: :triangle,
                pressure_curve_min: 0.0,
                pressure_curve_max: 0.0,
                pressure_curve_cycles_per_bar: 10.0,
                pressure_curve_shift_mbeats: 0.0,
                pressure_curve_anchor: :sample,
                pressure_mode: :add,
                error_prefix: "strum"
              }
            }
          }
        },
        %Mensch.SampleEntry{
          chord_spec: %Mensch.Harmony.ChordSpec{
            root: :f,
            tones: nil,
            quality: :maj9,
            octave: 3,
            inversion: 0,
            voicing: %Mensch.Harmony.ChordSpec.Voicing{
              type: :close,
              center_note: 47,
              range_min: 21,
              range_max: 108,
              voice_count: nil,
              doubling: :auto,
              inversion_resolution_mode: :per_step_centered
            },
            min_voice_count: 5,
            foreign_bass: nil
          },
          timeline_context: %Mensch.TimelineContext{
            start_beat: %Mensch.BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %Mensch.Machines.Strum{
            params: %Mensch.Machines.StrumParams{
              velocity: 100,
              modulation_strategy: %Mensch.Machines.Strum.NoteModulationStrategies.StrumEnvelopedPressure{
                pressure_attack_mbeats: 50.0,
                pressure_decay_mbeats: 280.0,
                pressure_release_mbeats: 120.0,
                pressure_sustain_level: 0.68,
                slide_peak_value: 125.0,
                pressure_curve: :triangle,
                pressure_curve_min: 0.0,
                pressure_curve_max: 0.0,
                pressure_curve_cycles_per_bar: 10.0,
                pressure_curve_shift_mbeats: 0.0,
                pressure_curve_anchor: :sample,
                pressure_mode: :add,
                error_prefix: "strum"
              }
            }
          }
        },
        %Mensch.SampleEntry{
          chord_spec: %Mensch.Harmony.ChordSpec{
            root: :b_flat,
            tones: nil,
            quality: :maj9,
            octave: 3,
            inversion: 0,
            voicing: %Mensch.Harmony.ChordSpec.Voicing{
              type: :close,
              center_note: 47,
              range_min: 21,
              range_max: 108,
              voice_count: nil,
              doubling: :auto,
              inversion_resolution_mode: :per_step_centered
            },
            min_voice_count: 5,
            foreign_bass: nil
          },
          timeline_context: %Mensch.TimelineContext{
            start_beat: %Mensch.BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %Mensch.Machines.Strum{
            params: %Mensch.Machines.StrumParams{
              velocity: 100,
              modulation_strategy: %Mensch.Machines.Strum.NoteModulationStrategies.StrumEnvelopedPressure{
                pressure_attack_mbeats: 50.0,
                pressure_decay_mbeats: 280.0,
                pressure_release_mbeats: 120.0,
                pressure_sustain_level: 0.68,
                slide_peak_value: 125.0,
                pressure_curve: :triangle,
                pressure_curve_min: 0.0,
                pressure_curve_max: 0.0,
                pressure_curve_cycles_per_bar: 10.0,
                pressure_curve_shift_mbeats: 0.0,
                pressure_curve_anchor: :sample,
                pressure_mode: :add,
                error_prefix: "strum"
              }
            }
          }
        }
      ]
    }
  end
end
