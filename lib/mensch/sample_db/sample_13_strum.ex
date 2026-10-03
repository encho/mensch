defmodule Mensch.SampleDb.Sample13Strum do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.Strum
  alias Mensch.Machines.Strum.NoteModulationStrategies.StrumEnvelopedPressure
  alias Mensch.Machines.StrumParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
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

    %{
      id: "sample-13-strum",
      folder: "Strum",
      name: "Strum Sustain Progression",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :a, modifier: :min7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :f, modifier: :maj7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 3, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: machine
        }
      ]
    }
  end
end
