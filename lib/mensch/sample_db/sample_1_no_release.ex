defmodule Mensch.SampleDb.Sample1NoRelease do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.StrummedMpe
  alias Mensch.Machines.StrummedMpeParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    no_release_params = %StrummedMpeParams{
      StrummedMpeParams.default()
      | release_mbeats: 0,
        attack_mbeats: 300,
        note_stagger_mbeats: 220
    }

    %{
      id: "sample-1-no-release",
      folder: "Legacy",
      name: "StrummedMpe · Cm7 F7 Bbmaj7 Gm7 · No Release",
      sample_context:
        SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: %StrummedMpe{params: no_release_params}
        },
        %{
          chord_spec: %ChordSpec{root: :f, modifier: :dom7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 3, mbeat: 0},
            duration_mbeats: 9000
          },
          machine: %StrummedMpe{params: no_release_params}
        },
        %{
          chord_spec: %ChordSpec{root: :a_sharp, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 3, mbeat: 0},
            duration_mbeats: 9000
          },
          machine: %StrummedMpe{params: no_release_params}
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 5, beat: 3, mbeat: 0},
            duration_mbeats: 9000
          },
          machine: %StrummedMpe{params: no_release_params}
        }
      ]
    }
  end
end
