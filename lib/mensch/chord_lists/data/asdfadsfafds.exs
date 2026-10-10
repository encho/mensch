%{
  id: "asdfadsfafds",
  name: "asdfadsfafds",
  version: 1,
  entries: [
    %{
      id: "19",
      parameters: %Mensch.Harmony.ChordSpec.Parameters{
        root: :c,
        quality: :maj7,
        octave: 3,
        inversion: 0,
        voicing_type: :close,
        inversion_tracking_mode: :per_step_centered,
        center_note: 60,
        range_min: nil,
        range_max: nil,
        voice_count: nil,
        doubling: :auto,
        foreign_bass_mode: :relative,
        foreign_bass_pitch_class: nil,
        foreign_bass_octave: 0
      },
      inserted_at: "2026-10-10T16:34:34Z",
      snapshot: %{
        voiced_chord_tones: [48, 52, 55, 59],
        final_note_details: [
          %Mensch.Harmony.Resolver.NoteDetail{
            midi_note: 48,
            named_note_name: "C3",
            named_note_note: "C",
            named_note_octave: 3,
            note_distance: 0,
            degree_simple: "1",
            degree_compound_preferred: "1",
            interval_human_label: "Perfect unison",
            chord_tone_role: "root"
          },
          %Mensch.Harmony.Resolver.NoteDetail{
            midi_note: 52,
            named_note_name: "E3",
            named_note_note: "E",
            named_note_octave: 3,
            note_distance: 4,
            degree_simple: "3",
            degree_compound_preferred: "3",
            interval_human_label: "Major third",
            chord_tone_role: "chord_tone"
          },
          %Mensch.Harmony.Resolver.NoteDetail{
            midi_note: 55,
            named_note_name: "G3",
            named_note_note: "G",
            named_note_octave: 3,
            note_distance: 7,
            degree_simple: "5",
            degree_compound_preferred: "5",
            interval_human_label: "Perfect fifth",
            chord_tone_role: "chord_tone"
          },
          %Mensch.Harmony.Resolver.NoteDetail{
            midi_note: 59,
            named_note_name: "B3",
            named_note_note: "B",
            named_note_octave: 3,
            note_distance: 11,
            degree_simple: "7",
            degree_compound_preferred: "7",
            interval_human_label: "Major seventh",
            chord_tone_role: "chord_tone"
          }
        ],
        final_notes: [48, 52, 55, 59],
        foreign_bass_note: nil,
        inverted_chord_tones: [48, 52, 55, 59],
        resolved_chord_tones: [48, 52, 55, 59]
      }
    }
  ],
  inserted_at: "2026-10-10T16:34:31Z",
  updated_at: "2026-10-10T16:34:34Z"
}
