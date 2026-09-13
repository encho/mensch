defmodule Mensch.SampleDb.Sample6SimpleChordCMajorInversions do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.SimpleChord
  alias Mensch.Machines.SimpleChordParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    machine = %SimpleChord{params: SimpleChordParams.default()}

    %{
      id: "sample-6-simple-chord-c-major-inversions",
      folder: "Simple Chord",
      name: "SimpleChord · C Maj7 Inversions · 2 Beats",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 1},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 2, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 2},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 3},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 2, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 4},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 5},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 2, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 0, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: -1},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 3, beat: 2, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: -2},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: -3},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 2, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: -4},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 5, beat: 0, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: -5},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 5, beat: 2, mbeat: 0},
            duration_mbeats: 2000
          },
          machine: machine
        }
      ]
    }
  end
end
