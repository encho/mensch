defmodule Mensch.SampleDb.Sample12RootNote do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.RootNote
  alias Mensch.Machines.RootNoteParams
  alias Mensch.NewModulation.LfoCurve
  alias Mensch.NewModulation.LfoGroup
  alias Mensch.NewModulation.LfoRamp
  alias Mensch.NewModulation.LfoSaw
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  # Example: non-cyclic linear ramp (holds once it reaches the end).
  #
  @lfo_pressure_ramp %LfoGroup{
    initial: %Mensch.NewModulation.LfoRamp{
      start_value: 0.0,
      end_value: 47.0,
      interpolation_function: :linear,
      span_mbeats: 3000.0,
      shift_mbeats: 1000.0,
      anchor: :note
    },
    operations: []
  }

  @lfo_pressure_saw %LfoGroup{
    initial: %LfoSaw{
      curve: :saw_up,
      scale: 47.0,
      cycles_per_bar: 1.0,
      shift_mbeats: 0.0,
      polarity: :bipolar,
      anchor: :note,
      drop_phase: 0.75
    },
    operations: []
  }

  @lfo_pressure_group %LfoGroup{
    initial: %LfoCurve{
      curve: :sine,
      scale: 30.0,
      cycles_per_bar: 10.0,
      shift_mbeats: 0.0,
      polarity: :bipolar,
      anchor: :note
    },
    operations: [
      {:multiply,
       %LfoRamp{
         start_value: 0.0,
         end_value: 1.0,
         interpolation_function: :linear,
         span_mbeats: 4000.0,
         shift_mbeats: 0,
         anchor: :note
       }}
    ]
  }

  @spec sample(pos_integer()) :: map()
  def sample(frame_mbeats) when is_integer(frame_mbeats) and frame_mbeats > 0 do
    %{
      id: "sample-12-root-note",
      folder: "Root Note",
      name: "Root Note Offsets",
      sample_context:
        SampleContext.new!(%{bpm: 100, time_signature: {4, 4}, frame_mbeats: frame_mbeats}),
      sample_entries: [
        %{
          chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 3, inversion: 2},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{
              RootNoteParams.default()
              | octave_offset: -1,
                lfo_pressure: %{lfo: @lfo_pressure_saw, mode: :add}
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :f, modifier: :dom7, octave: 3, inversion: 1},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{
              RootNoteParams.default()
              | octave_offset: -1,
                lfo_pressure: %{lfo: @lfo_pressure_ramp, mode: :add}
            }
          }
        },
        %{
          chord_spec: %ChordSpec{root: :a_sharp, modifier: :maj7, octave: 3, inversion: 3},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{
              RootNoteParams.default()
              | octave_offset: -1,
                lfo_pressure: %{lfo: @lfo_pressure_group, mode: :add}
            }
          }
        }
      ]
    }
  end
end
