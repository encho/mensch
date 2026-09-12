defmodule Mensch.SampleDb.Sample0SimpleChordTraversal do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machine.VoicingStrategies.Traversal
  alias Mensch.Machines.SimpleChord
  alias Mensch.Machines.SimpleChordParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    params = %SimpleChordParams{
      SimpleChordParams.default()
      | voicing_strategy:
          Traversal.new(
            direction: :ping_pong,
            octave_min_offset: 0,
            octave_max_offset: 1,
            cycle_count: 2
          ),
        stagger_mbeats: 700,
        note_length_mode: :equal,
        attack_mbeats: 120,
        decay_mbeats: 180,
        release_mbeats: 140,
        attack_curve: :exp,
        decay_curve: :log,
        release_curve: :s_curve,
        sustain_level: 0.68
    }

    machine = %SimpleChord{params: params}

    %{
      id: "sample-0-simple-chord-traversal",
      name: "Sample 0 · Simple Chord Traversal Ping Pong",
      sample_context:
        SampleContext.new!(%{bpm: 104, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :a, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :f, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :dom7, octave: 4, inversion: 0},
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
