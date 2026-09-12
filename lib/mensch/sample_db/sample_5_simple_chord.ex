defmodule Mensch.SampleDb.Sample5SimpleChord do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.SimpleChord
  alias Mensch.Machines.SimpleChordParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    # Preset A (active): hard-gated articulation
    # params = %SimpleChordParams{
    #   SimpleChordParams.default()
    #   | stagger_mbeats: 1000,
    #     note_length_mode: :align_end,
    #     attack_mbeats: 0,
    #     decay_mbeats: 0,
    #     release_mbeats: 0,
    #     attack_curve: :exp,
    #     decay_curve: :log,
    #     release_curve: :s_curve
    # }

    # Preset B (commented): longer envelope tail for smoother phrasing
    params = %SimpleChordParams{
      SimpleChordParams.default()
      | stagger_mbeats: 600,
        # note_length_mode: :align_end,
        note_length_mode: :equal,
        attack_mbeats: 300,
        decay_mbeats: 320,
        release_mbeats: 0,
        attack_curve: :exp,
        decay_curve: :log,
        release_curve: :s_curve
    }

    machine = %SimpleChord{params: params}

    %{
      id: "sample-5-simple-chord",
      name: "SimpleChord · Bb Key Curves",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :f, modifier: :dom7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :a_sharp, modifier: :maj7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :g, modifier: :min7, octave: 4, inversion: 0},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{root: :d_sharp, modifier: :maj7, octave: 4, inversion: 0},
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
