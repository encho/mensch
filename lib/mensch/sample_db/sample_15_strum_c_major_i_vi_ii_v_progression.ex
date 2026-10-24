defmodule Mensch.SampleDb.Sample15StrumCMajorIViIiVProgression do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Machines.Strum
  alias Mensch.Machines.Strum.NoteModulationStrategies.StrumEnvelopedPressure
  alias Mensch.Machines.StrumParams
  alias Mensch.SampleContext
  alias Mensch.SampleDefinition
  alias Mensch.SampleEntry
  alias Mensch.TimelineContext

  @behaviour Mensch.SampleDefinition.Provider
  @spec sample(pos_integer()) :: SampleDefinition.t()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    machine =
      %Strum{
        params: %StrumParams{
          velocity: 100,
          modulation_strategy: %StrumEnvelopedPressure{
            error_prefix: "strum",
            pressure_attack_mbeats: 80.0,
            pressure_decay_mbeats: 200.0,
            pressure_release_mbeats: 120.0,
            slide_peak_value: 90
          }
        }
      }

    %SampleDefinition{
      id: "sample-15-strum-c-major-i-vi-ii-v-progression",
      created_at: ~U[2026-01-01 00:00:00Z],
      folder: "Strum",
      name: "Cmajor I-vi-ii-V Progression",
      total_length_bars: 64,
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :c, quality: :maj7},
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :c, quality: :maj7},
            octave: 3,
            inversion: 1
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :c, quality: :maj7},
            octave: 3,
            inversion: 2
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 8, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :c, quality: :maj7},
            octave: 3,
            inversion: 3
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 12, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :a, quality: :min7},
            octave: 2,
            inversion: 1
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 16, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :a, quality: :min7},
            octave: 2,
            inversion: 2
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 20, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :a, quality: :min7},
            octave: 2,
            inversion: 3
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 24, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :a, quality: :min7},
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 28, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :d, quality: :min7},
            octave: 2,
            inversion: 3
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 32, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :d, quality: :min7},
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 36, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :d, quality: :min7},
            octave: 3,
            inversion: 1
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 40, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :d, quality: :min7},
            octave: 3,
            inversion: 2
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 44, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :g, quality: :dom7},
            octave: 2,
            inversion: 1
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 48, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :g, quality: :dom7},
            octave: 2,
            inversion: 2
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 52, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :g, quality: :dom7},
            octave: 2,
            inversion: 3
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 56, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :g, quality: :dom7},
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 60, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        }
      ]
    }
  end
end
