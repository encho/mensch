defmodule Mensch.SampleDb.GeneratedChordListGeneratedSample49 do
  @moduledoc false

  alias Mensch.SampleBlueprint
  alias Mensch.SampleDefinition

  @behaviour Mensch.SampleDefinition.Provider

  @spec sample(pos_integer()) :: SampleDefinition.t()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    SampleBlueprint.build!(%{
      id: "chord_list_generated_sample-49",
      created_at: ~U[2026-10-17 15:56:40Z],
      folder: "Generated",
      name: "Chord List Generated Sample",
      blueprint_id: "progression__steady_strum__strum1",
      bpm: 120,
      time_signature: {4, 4},
      frame_mbeats: frame_mbeats,
      chord_duration_mbeats: 4000,
      silence_after_chord_mbeats: 0,
      blueprint_additional_params: %{
  "pressure_attack_mbeats" => 50.0,
  "pressure_curve" => "triangle",
  "velocity" => 100
},
      chords: [
        %{
  root: :d,
  octave: 3,
  inversion: 0,
  foreign_bass: nil,
  min_voice_count: 4,
  quality: :min7,
  tones: nil,
  voicing: %Mensch.Harmony.ChordSpec.Voicing{
    type: :close,
    center_note: 47,
    range_min: 21,
    range_max: 108,
    voice_count: nil,
    doubling: :auto,
    inversion_resolution_mode: :per_step_centered
  }
},
      %{
  root: :f,
  octave: 3,
  inversion: 0,
  foreign_bass: nil,
  min_voice_count: 5,
  quality: :maj9,
  tones: nil,
  voicing: %Mensch.Harmony.ChordSpec.Voicing{
    type: :close,
    center_note: 47,
    range_min: 21,
    range_max: 108,
    voice_count: nil,
    doubling: :auto,
    inversion_resolution_mode: :per_step_centered
  }
},
      %{
  root: :b_flat,
  octave: 3,
  inversion: 0,
  foreign_bass: nil,
  min_voice_count: 5,
  quality: :maj9,
  tones: nil,
  voicing: %Mensch.Harmony.ChordSpec.Voicing{
    type: :close,
    center_note: 47,
    range_min: 21,
    range_max: 108,
    voice_count: nil,
    doubling: :auto,
    inversion_resolution_mode: :per_step_centered
  }
}
      ]
    })
  end
end
