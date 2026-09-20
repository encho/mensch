defmodule Mensch.SampleDb.Sample12RootNote do
  @moduledoc false

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machines.RootNote
  alias Mensch.Machines.RootNoteParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

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
            params: %RootNoteParams{RootNoteParams.default() | octave_offset: -1}
          }
        },
        %{
          chord_spec: %ChordSpec{root: :f, modifier: :dom7, octave: 3, inversion: 1},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 1, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{RootNoteParams.default() | octave_offset: -1}
          }
        },
        %{
          chord_spec: %ChordSpec{root: :a_sharp, modifier: :maj7, octave: 3, inversion: 3},
          timeline_context: %TimelineContext{
            start_beat: %BeatPosition{bar: 2, beat: 0, mbeat: 0},
            duration_mbeats: 4000
          },
          machine: %RootNote{
            params: %RootNoteParams{RootNoteParams.default() | octave_offset: -1}
          }
        }
      ]
    }
  end
end
