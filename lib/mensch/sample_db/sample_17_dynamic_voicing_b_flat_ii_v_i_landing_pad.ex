defmodule Mensch.SampleDb.Sample17DynamicVoicingBFlatIiVILandingPad do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicing.NoteModulationStrategies.DynamicVoicingEnvelopedPressure
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.SampleDefinition
  alias Mensch.SampleEntry
  alias Mensch.TimelineContext

  @behaviour Mensch.SampleDefinition.Provider
  @spec sample(pos_integer()) :: SampleDefinition.t()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: {:cycle_up, 2},
          number_of_inversions: 6,
          modulation_strategy: %DynamicVoicingEnvelopedPressure{
            error_prefix: "dynamic_voicing",
            pressure_attack_mbeats: 70.0,
            pressure_decay_mbeats: 170.0,
            pressure_release_mbeats: 100.0
          }
        }
      }

    %SampleDefinition{
      id: "sample-17-dynamic-voicing-b-flat-ii-v-i-landing-pad",
      created_at: ~U[2026-10-27 00:00:00Z],
      folder: "Dynamic Voicing",
      name: "Bb ii-V-I Landing Pad (Dynamic Voicing)",
      total_length_bars: 8,
      sample_context:
        SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{inversion_resolution_mode: :anchor_then_wander},
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
            voicing: %ChordSpec.Voicing{inversion_resolution_mode: :anchor_then_wander},
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
            voicing: %ChordSpec.Voicing{inversion_resolution_mode: :anchor_then_wander},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :b_flat, quality: :maj7},
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %SampleEntry{
          chord_spec: %ChordSpec{
            voicing: %ChordSpec.Voicing{inversion_resolution_mode: :anchor_then_wander},
            harmonic_identity: %ChordSpec.HarmonicIdentity{root: :b_flat, quality: :maj7},
            octave: 3,
            inversion: 0
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 6, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        }
      ]
    }
  end
end
