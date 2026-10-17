defmodule Mensch.SampleDb.Sample12RootNote do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Machines.RootNote
  alias Mensch.Machines.RootNote.NoteModulationStrategies.RootNoteEnvelopedPressure
  alias Mensch.Machines.RootNoteParams
  alias Mensch.SampleContext
  alias Mensch.SampleDefinition
  alias Mensch.SampleEntry
  alias Mensch.TimelineContext

  @behaviour Mensch.SampleDefinition.Provider
  @spec sample(pos_integer()) :: SampleDefinition.t()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %SampleDefinition{
      id: "sample-12-root-note",
      created_at: ~U[2026-01-01 00:00:00Z],
      folder: "Root Note",
      name: "Root Note Offsets",
      total_length_bars: 5,
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            root: :c,
            quality: :maj7,
            octave: 3,
            inversion: 2
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{
              RootNoteParams.default()
              | octave_offset: -2,
                modulation_strategy: %RootNoteEnvelopedPressure{
                  error_prefix: "root_note",
                  pressure_attack_mbeats: 0,
                  pressure_decay_mbeats: 0,
                  pressure_release_mbeats: 0,
                  slide_peak_value: 100
                }
            }
          }
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            root: :f,
            quality: :dom7,
            octave: 3,
            inversion: 1
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{
              RootNoteParams.default()
              | octave_offset: -2,
                modulation_strategy: %RootNoteEnvelopedPressure{
                  error_prefix: "root_note",
                  pressure_attack_mbeats: 0,
                  pressure_decay_mbeats: 0,
                  pressure_release_mbeats: 0,
                  slide_peak_value: 100
                }
            }
          }
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            root: :a_sharp,
            quality: :maj7,
            octave: 3,
            inversion: 3
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{
              RootNoteParams.default()
              | octave_offset: -2,
                modulation_strategy: %RootNoteEnvelopedPressure{
                  error_prefix: "root_note",
                  pressure_attack_mbeats: 0,
                  pressure_decay_mbeats: 0,
                  pressure_release_mbeats: 0,
                  slide_peak_value: 100
                }
            }
          }
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            root: :d,
            quality: :min7,
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{
              RootNoteParams.default()
              | octave_offset: -2,
                modulation_strategy: %RootNoteEnvelopedPressure{
                  error_prefix: "root_note",
                  pressure_attack_mbeats: 0,
                  pressure_decay_mbeats: 0,
                  pressure_release_mbeats: 0,
                  slide_peak_value: 100
                }
            }
          }
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            root: :g,
            quality: :maj7,
            octave: 3,
            inversion: 1
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{
              RootNoteParams.default()
              | octave_offset: -2,
                modulation_strategy: %RootNoteEnvelopedPressure{
                  error_prefix: "root_note",
                  pressure_attack_mbeats: 0,
                  pressure_decay_mbeats: 0,
                  pressure_release_mbeats: 0,
                  slide_peak_value: 100
                }
            }
          }
        }
      ]
    }
  end
end
