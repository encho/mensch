defmodule Mensch.SampleDb.Sample2CMajorChords do
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
        note_stagger_mbeats: 180
    }

    %{
      id: "sample-2-c-major-chords",
      name: "Sample 2 · C Major ii-V-I-vi Turnaround · No Release",
      sample_context:
        SampleContext.new!(%{bpm: 80, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: %StrummedMpe{params: no_release_params}
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: %StrummedMpe{params: no_release_params}
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: %StrummedMpe{params: no_release_params}
        },
        %{
          chord_spec: %ChordSpec{root: :a, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 6, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: %StrummedMpe{params: no_release_params}
        }
      ]
    }
  end
end
