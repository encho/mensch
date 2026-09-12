defmodule Mensch.SampleDb.Sample3 do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.RootModulated
  alias Mensch.Machines.RootModulatedParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %{
      id: "sample-3",
      name: "RootModulated · Dm7 G7 Cmaj7 Root",
      sample_context:
        SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: %RootModulated{params: RootModulatedParams.default()}
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 3, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: %RootModulated{params: RootModulatedParams.default()}
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: %RootModulated{params: RootModulatedParams.default()}
        }
      ]
    }
  end
end
