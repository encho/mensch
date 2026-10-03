defmodule Mensch.SampleDb.Sample14StrumCMajorSixteenChords do
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

    key = %{tonic: :c, mode: :major}

    %{
      id: "sample-14-strum-c-major-16-chords",
      folder: "Strum",
      name: "C Major 16-Chord Palette (2 Bars + 2 Bars Rest)",
      total_length_bars: 64,
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{
            root: :d,
            quality: :min,
            octave: 3,
            inversion: 0,
            function: "ii",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :d,
            quality: :min7,
            octave: 3,
            inversion: 0,
            function: "ii",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 4, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :d,
            quality: :min9,
            octave: 3,
            inversion: 0,
            function: "ii",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 8, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :d,
            quality: :min11,
            octave: 3,
            inversion: 0,
            function: "ii",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 12, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :g,
            quality: :maj,
            octave: 3,
            inversion: 0,
            function: "V",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 16, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :g,
            quality: :dom7,
            octave: 3,
            inversion: 0,
            function: "V",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 20, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :g,
            quality: :dom9,
            octave: 3,
            inversion: 0,
            function: "V",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 24, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :g,
            quality: :dom13,
            octave: 3,
            inversion: 0,
            function: "V",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 28, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :f,
            quality: :maj,
            octave: 3,
            inversion: 0,
            function: "IV",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 32, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :f,
            quality: :maj7,
            octave: 3,
            inversion: 0,
            function: "IV",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 36, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :f,
            quality: :maj9,
            octave: 3,
            inversion: 0,
            function: "IV",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 40, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :f,
            quality: :six_nine,
            octave: 3,
            inversion: 0,
            function: "IV",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 44, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :c,
            quality: :maj,
            octave: 3,
            inversion: 0,
            function: "I",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 48, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :c,
            quality: :maj7,
            octave: 3,
            inversion: 0,
            function: "I",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 52, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :c,
            quality: :maj9,
            octave: 3,
            inversion: 0,
            function: "I",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 56, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        },
        %{
          chord_spec: %ChordSpec{
            root: :c,
            quality: :six_nine,
            octave: 3,
            inversion: 0,
            function: "I",
            key: key
          },
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 60, beat: 0, mbeat: 0},
            duration_mbeats: 8000
          },
          machine: machine
        }
      ]
    }
  end
end
