defmodule Mensch.RootNoteTest do
  use ExUnit.Case, async: true

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machine
  alias Mensch.Machines.RootNote
  alias Mensch.Machines.RootNoteParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  test "inversion does not affect generated root note" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    machine = %RootNote{params: RootNoteParams.default()}

    chord_inversion_0 = %ChordSpec{root: :c, modifier: :maj, octave: 3, inversion: 0}
    chord_inversion_2 = %ChordSpec{root: :c, modifier: :maj, octave: 3, inversion: 2}

    rendered_0 =
      Machine.build_frame_sequence(
        machine,
        chord_inversion_0,
        sample_context,
        timeline_context,
        []
      )

    rendered_2 =
      Machine.build_frame_sequence(
        machine,
        chord_inversion_2,
        sample_context,
        timeline_context,
        []
      )

    root_note_0 = rendered_0.frames |> first_note_on_note() |> Map.fetch!(:midi_note)
    root_note_2 = rendered_2.frames |> first_note_on_note() |> Map.fetch!(:midi_note)

    assert root_note_0 == 48
    assert root_note_2 == 48
  end

  test "octave_offset shifts root by whole octaves" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 3, inversion: 2}

    midi_note_for_offset = fn octave_offset ->
      params = %RootNoteParams{RootNoteParams.default() | octave_offset: octave_offset}
      machine = %RootNote{params: params}

      machine
      |> Machine.build_frame_sequence(chord_spec, sample_context, timeline_context, [])
      |> Map.fetch!(:frames)
      |> first_note_on_note()
      |> Map.fetch!(:midi_note)
    end

    assert midi_note_for_offset.(-1) == 36
    assert midi_note_for_offset.(0) == 48
    assert midi_note_for_offset.(1) == 60
  end

  test "emits one note lifecycle across full chord duration" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :f, modifier: :dom7, octave: 3, inversion: 3}

    machine = %RootNote{params: RootNoteParams.default()}

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    note_on_events =
      rendered.frames
      |> Enum.flat_map(fn frame ->
        frame.notes
        |> Enum.filter(& &1.note_on)
        |> Enum.map(fn note -> {frame.at_mbeat, note} end)
      end)

    note_off_events =
      rendered.frames
      |> Enum.flat_map(fn frame ->
        frame.notes
        |> Enum.filter(& &1.note_off)
        |> Enum.map(fn note -> {frame.at_mbeat, note} end)
      end)

    assert length(note_on_events) == 1
    assert length(note_off_events) == 1

    {note_on_mbeat, note_on_note} = hd(note_on_events)
    {note_off_mbeat, note_off_note} = hd(note_off_events)

    assert note_on_mbeat == 0
    assert note_off_mbeat == 4000
    assert note_on_note.note_instance_id == 0
    assert note_off_note.note_instance_id == 0
    assert note_on_note.slide == 0
    assert note_on_note.bend == 0.0
  end

  defp first_note_on_note(frames) do
    frames
    |> Enum.find_value(fn frame ->
      Enum.find(frame.notes, & &1.note_on)
    end)
  end
end
