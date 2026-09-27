defmodule Mensch.SampleDb.Sample10DynamicVoicingBFlatIIiivv do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.Modulation.LfoCurve
  alias Mensch.Modulation.LfoGroup
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @lfo_pressure %LfoGroup{
    initial: %LfoCurve{
      curve: :sine,
      min_value: -0.25,
      max_value: 0.25,
      cycles_per_bar: 20.0,
      shift_mbeats: 0.0,
      anchor: :sample
    },
    operations: []
  }

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    frame_mbeats = 20

    %{
      id: "sample-10-dynamic-voicing-bb-i-ii-iv-v",
      folder: "Dynamic Voicing",
      name: "Bb Major (I-ii-IV-V) · cycle_up 2",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :a_sharp, modifier: :maj7, octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: {:cycle_up, 2},
              number_of_inversions: 4,
              envelope_attack_mbeats: 5.0,
              envelope_decay_mbeats: 10.0,
              envelope_release_mbeats: 5.0,
              lfo_pressure: %{lfo: @lfo_pressure, mode: :add}
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :min7, octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: {:cycle_up, 2},
              number_of_inversions: 4,
              envelope_attack_mbeats: 5.0,
              envelope_decay_mbeats: 10.0,
              envelope_release_mbeats: 5.0,
              lfo_pressure: %{lfo: @lfo_pressure, mode: :add}
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :d_sharp, modifier: :maj7, octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: {:cycle_up, 2},
              number_of_inversions: 4,
              envelope_attack_mbeats: 5.0,
              envelope_decay_mbeats: 10.0,
              envelope_release_mbeats: 5.0,
              lfo_pressure: %{lfo: @lfo_pressure, mode: :add}
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :f, modifier: :dom7, octave: 2, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: {:cycle_up, 2},
              number_of_inversions: 4,
              envelope_attack_mbeats: 5.0,
              envelope_decay_mbeats: 10.0,
              envelope_release_mbeats: 5.0,
              lfo_pressure: %{lfo: @lfo_pressure, mode: :add}
            }
          }
        }
      ]
    }
  end
end
