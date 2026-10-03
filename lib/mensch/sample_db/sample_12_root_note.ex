defmodule Mensch.SampleDb.Sample12RootNote do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.RootNote
  alias Mensch.Machines.RootNote.NoteModulationStrategies.RootNoteEnvelopedPressure
  alias Mensch.Machines.RootNoteParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %{
      id: "sample-12-root-note",
      folder: "Root Note",
      name: "Root Note Offsets",
      total_length_bars: 5,
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, tones: ["1", "3", "5", "7"], octave: 3, inversion: 2},
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
        %{
          chord_spec: %ChordSpec{root: :f, tones: ["1", "3", "5", "b7"], octave: 3, inversion: 1},
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
        %{
          chord_spec: %ChordSpec{
            root: :a_sharp,
            tones: ["1", "3", "5", "7"],
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
        %{
          chord_spec: %ChordSpec{root: :d, tones: ["1", "b3", "5", "b7"], octave: 3, inversion: 0},
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
        %{
          chord_spec: %ChordSpec{root: :g, tones: ["1", "3", "5", "7"], octave: 3, inversion: 1},
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
