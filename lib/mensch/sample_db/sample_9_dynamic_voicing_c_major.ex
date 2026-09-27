defmodule Mensch.SampleDb.Sample9DynamicVoicingCMajor do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.Modulation.LfoCurve
  alias Mensch.Modulation.LfoGroup
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @lfo_slide %LfoGroup{
    initial: %LfoCurve{
      curve: :sine,
      min_value: 0.0,
      max_value: 1.0,
      cycles_per_bar: 6.0,
      shift_mbeats: 0.0,
      anchor: :note
    },
    operations: []
  }

  @lfo_pressure %LfoGroup{
    initial: %LfoCurve{
      curve: :sine,
      min_value: -0.3,
      max_value: 0.3,
      cycles_per_bar: 20.0,
      shift_mbeats: 0.0,
      anchor: :note
    },
    operations: []
  }

  @lfo_bend %LfoGroup{
    initial: %LfoCurve{
      curve: :sine,
      min_value: -0.001,
      max_value: 0.001,
      cycles_per_bar: 3.0,
      shift_mbeats: 0.0,
      anchor: :note
    },
    operations: []
  }

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %{
      id: "sample-9-dynamic-voicing-c-major",
      folder: "Dynamic Voicing",
      name: "C Major Jazz Cycle (ii-V-I-vi)",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 10,
              envelope_attack_mbeats: 5.0,
              envelope_decay_mbeats: 10.0,
              envelope_release_mbeats: 5.0,
              lfo_slide: %{lfo: @lfo_slide, mode: :add},
              lfo_pressure: %{lfo: @lfo_pressure, mode: :add},
              lfo_bend: %{lfo: @lfo_bend, mode: :add}
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 10,
              envelope_attack_mbeats: 5.0,
              envelope_decay_mbeats: 10.0,
              envelope_release_mbeats: 5.0,
              lfo_slide: %{lfo: @lfo_slide, mode: :add},
              lfo_pressure: %{lfo: @lfo_pressure, mode: :add},
              lfo_bend: %{lfo: @lfo_bend, mode: :add}
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 10,
              envelope_attack_mbeats: 5.0,
              envelope_decay_mbeats: 10.0,
              envelope_release_mbeats: 5.0,
              lfo_slide: %{lfo: @lfo_slide, mode: :add},
              lfo_pressure: %{lfo: @lfo_pressure, mode: :add},
              lfo_bend: %{lfo: @lfo_bend, mode: :add}
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :a, modifier: :min7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %DynamicVoicing{
            params: %DynamicVoicingParams{
              direction: :up,
              number_of_inversions: 10,
              envelope_attack_mbeats: 5.0,
              envelope_decay_mbeats: 10.0,
              envelope_release_mbeats: 5.0,
              lfo_slide: %{lfo: @lfo_slide, mode: :add},
              lfo_pressure: %{lfo: @lfo_pressure, mode: :add},
              lfo_bend: %{lfo: @lfo_bend, mode: :add}
            }
          }
        }
      ]
    }
  end
end
