defmodule Mensch.NoteLifecycleTest do
  use ExUnit.Case, async: true

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Envelope.ADSR
  alias Mensch.Machine
  alias Mensch.Machines.SimpleChord
  alias Mensch.Machines.SimpleChordParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  test "adsr ends after total duration" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})
    adsr = ADSR.from_mbeats(1000, sample_context, %{release_mbeats: 0})

    assert ADSR.phase_at_mbeat(adsr, 1001) == :ended
    assert ADSR.level_at_mbeat(adsr, 1001) == 0.0
    refute ADSR.in_sustain_mbeat?(adsr, 1001)
  end

  test "simple chord with release 0 emits no frames for note after note_off" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0}

    params =
      %SimpleChordParams{SimpleChordParams.default() | stagger_mbeats: 1000, release_mbeats: 0}

    machine = %SimpleChord{params: params}

    performance =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    first_note_frames =
      performance.frames
      |> Enum.flat_map(fn frame ->
        case Enum.find(frame.notes, fn note -> note.note_instance_id == 0 end) do
          nil -> []
          note -> [{frame.at_mbeat, note}]
        end
      end)

    assert Enum.count(first_note_frames, fn {_at_mbeat, note} -> note.note_off end) == 1

    {first_note_off_mbeat, _note_off_frame_note} =
      Enum.find(first_note_frames, fn {_at_mbeat, note} -> note.note_off end)

    trailing_frames =
      Enum.filter(first_note_frames, fn {at_mbeat, _note} -> at_mbeat > first_note_off_mbeat end)

    assert trailing_frames == []
  end

  test "simple chord align_end mode makes all notes end together" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0}

    params =
      %SimpleChordParams{
        SimpleChordParams.default()
        | stagger_mbeats: 1000,
          release_mbeats: 0,
          note_length_mode: :align_end
      }

    machine = %SimpleChord{params: params}

    performance =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    note_offs_by_index =
      performance.frames
      |> Enum.flat_map(fn frame ->
        frame.notes
        |> Enum.filter(& &1.note_off)
        |> Enum.map(fn note -> {note.note_instance_id, frame.at_mbeat} end)
      end)
      |> Map.new()

    assert map_size(note_offs_by_index) == 4
    assert Enum.uniq(Map.values(note_offs_by_index)) == [4000]
  end

  test "simple chord equal mode makes last note end at chord end" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0}

    params =
      %SimpleChordParams{
        SimpleChordParams.default()
        | stagger_mbeats: 1000,
          release_mbeats: 0,
          note_length_mode: :equal
      }

    machine = %SimpleChord{params: params}

    performance =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    note_offs_by_index =
      performance.frames
      |> Enum.flat_map(fn frame ->
        frame.notes
        |> Enum.filter(& &1.note_off)
        |> Enum.map(fn note -> {note.note_instance_id, frame.at_mbeat} end)
      end)
      |> Map.new()

    assert map_size(note_offs_by_index) == 4
    assert Map.fetch!(note_offs_by_index, 3) == 4000
    assert Enum.max(Map.values(note_offs_by_index)) == 4000
  end
end
