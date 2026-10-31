%{
  id: "empty_progression",
  version: 1,
  progression: %Mensch.Harmony.ChordProgression{
    name: "Empty Progression",
    description: "Starts with no chords.",
    chords: [
      %Mensch.Harmony.ChordSpec{
        harmonic_identity: %Mensch.Harmony.ChordSpec.HarmonicIdentity{
          root: :c,
          quality: :dim7,
          foreign_bass: nil
        },
        octave: 3,
        inversion: 0,
        voicing: %Mensch.Harmony.ChordSpec.Voicing{
          type: :close,
          center_note: 60,
          range_min: nil,
          range_max: nil,
          voice_count: nil,
          doubling: :auto,
          inversion_resolution_mode: :per_step_centered
        },
        min_voice_count: 4,
        foreign_bass: nil
      }
    ]
  },
  inserted_at: "2026-10-31T16:08:47Z",
  updated_at: "2026-10-31T16:08:47Z"
}
