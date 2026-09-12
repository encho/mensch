defmodule Mensch.SampleDb.Sample2 do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.StrummedMpe
  alias Mensch.Machines.StrummedMpeParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %{
      id: "sample-2",
      name: "Sample 2 · Cmaj7 Drone",
      sample_context:
        SampleContext.new!(%{bpm: 80, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 16000
          },
          machine: %StrummedMpe{params: StrummedMpeParams.default()}
        }
      ]
    }
  end
end
