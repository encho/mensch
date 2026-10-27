defmodule Mensch.SampleDb.Sample16StrumBFlatIiVILandingPad do
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
      id: "sample-16-strum-b-flat-ii-v-i-landing-pad",
      created_at: ~U[2026-10-27 00:00:00Z],
      folder: "Strum",
      name: "Bb ii-V-I Landing Pad (2+2+4)",
      total_length_bars: 8,
      sample_context:
        SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :c, quality: :min7},
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
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :f, quality: :dom7},
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :b_flat, quality: :maj7},
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 16000
          },
          machine: machine
        }
      ]
    }
  end
end
