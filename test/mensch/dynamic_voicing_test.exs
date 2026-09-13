defmodule Mensch.DynamicVoicingTest do
  use ExUnit.Case, async: true

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machine
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  test "number_of_inversions must be >= 1" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0}

    machine = %DynamicVoicing{
      params: %DynamicVoicingParams{direction: :up, number_of_inversions: 0}
    }

    assert_raise ArgumentError, ~r/number_of_inversions must be >= 1/, fn ->
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])
    end
  end

  test "swaps one note at each inversion boundary while other notes continue" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 3000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{direction: :up, number_of_inversions: 3}
      }

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    frame_0 = Enum.find(rendered.frames, &(&1.at_mbeat == 0))
    frame_1000 = Enum.find(rendered.frames, &(&1.at_mbeat == 1000))
    frame_2000 = Enum.find(rendered.frames, &(&1.at_mbeat == 2000))

    assert Enum.count(frame_0.notes, & &1.note_on) == 3

    assert Enum.count(frame_1000.notes, & &1.note_on) == 1
    assert Enum.count(frame_1000.notes, & &1.note_off) == 1

    assert Enum.count(frame_2000.notes, & &1.note_on) == 1
    assert Enum.count(frame_2000.notes, & &1.note_off) == 1
  end

  test "all sounding notes end at chord duration" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 3000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{direction: :down, number_of_inversions: 3}
      }

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    off_events =
      rendered.frames
      |> Enum.flat_map(fn frame ->
        frame.notes
        |> Enum.filter(& &1.note_off)
        |> Enum.map(fn note -> {note.note_instance_id, frame.at_mbeat} end)
      end)
      |> Map.new()

    assert map_size(off_events) == 5
    assert Enum.count(Map.values(off_events), &(&1 == 3000)) == 3
  end
end
