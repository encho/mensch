defmodule Mensch.SampleDb.GeneratedChordListGeneratedSample3 do
  @moduledoc false

  alias Mensch.SampleBlueprint
  alias Mensch.SampleDefinition

  @behaviour Mensch.SampleDefinition.Provider

  @spec sample(pos_integer()) :: SampleDefinition.t()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    SampleBlueprint.build!(%{
      id: "chord_list_generated_sample-3",
      created_at: ~U[2026-01-01 00:00:00Z],
      folder: "Generated",
      name: "Chord List Generated Sample",
      blueprint_id: "progression__alternating_wander__dv1",
      bpm: 120,
      time_signature: {4, 4},
      frame_mbeats: frame_mbeats,
      chord_duration_mbeats: 4000,
      silence_after_chord_mbeats: 0,
      blueprint_additional_params: %{
        "direction_mode" => "alternate",
        "number_of_inversions" => 8,
        "pressure_attack_mbeats" => 50.0
      },
      chords: [
        %{
          root: :c,
          octave: 3,
          inversion: 0,
          foreign_bass: nil,
          min_voice_count: 4,
          quality: :maj7,
          tones: nil,
          voicing: %Mensch.Harmony.ChordSpec.Voicing{
            type: :close,
            center_note: 60,
            range_min: nil,
            range_max: nil,
            voice_count: nil,
            doubling: :auto,
            inversion_resolution_mode: :per_step_centered
          }
        },
        %{
          root: :c,
          octave: 3,
          inversion: 0,
          foreign_bass: nil,
          min_voice_count: 5,
          quality: :min7_add11,
          tones: nil,
          voicing: %Mensch.Harmony.ChordSpec.Voicing{
            type: :close,
            center_note: 60,
            range_min: nil,
            range_max: nil,
            voice_count: nil,
            doubling: :auto,
            inversion_resolution_mode: :per_step_centered
          }
        },
        %{
          root: :e_flat,
          octave: 3,
          inversion: 0,
          foreign_bass: nil,
          min_voice_count: 4,
          quality: :maj7,
          tones: nil,
          voicing: %Mensch.Harmony.ChordSpec.Voicing{
            type: :close,
            center_note: 60,
            range_min: nil,
            range_max: nil,
            voice_count: nil,
            doubling: :auto,
            inversion_resolution_mode: :per_step_centered
          }
        }
      ]
    })
  end
end
