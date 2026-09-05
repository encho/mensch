defmodule Mensch.Machine.RootNoteTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.ResolvedChord
  alias Mensch.Machine.RootNote
  alias Mensch.Performance.Event

  @machine %RootNote{octave: 3, velocity: 90, note_length: 1.0}
  @context %{start_beat: 0.0, duration_beats: 4.0}

  test "Dm7 -> D3" do
    resolved_chord = %ResolvedChord{
      root: :d,
      notes: [:d, :f, :a, :c],
      degree: :ii,
      modifier: :min7
    }

    assert RootNote.generate(resolved_chord, @machine, @context) == [
             %Event{type: :note_on, at_beat: 0.0, note: {:d, 3}, velocity: 90},
             %Event{type: :note_off, at_beat: 4.0, note: {:d, 3}}
           ]
  end

  test "G7 -> G3" do
    resolved_chord = %ResolvedChord{
      root: :g,
      notes: [:g, :b, :d, :f],
      degree: :V,
      modifier: :dom7
    }

    assert [%Event{type: :note_on, note: {:g, 3}}, %Event{type: :note_off, note: {:g, 3}}] =
             RootNote.generate(resolved_chord, @machine, @context)
  end

  test "Cmaj7 -> C3" do
    resolved_chord = %ResolvedChord{
      root: :c,
      notes: [:c, :e, :g, :b],
      degree: :I,
      modifier: :maj7
    }

    assert [%Event{type: :note_on, note: {:c, 3}}, %Event{type: :note_off, note: {:c, 3}}] =
             RootNote.generate(resolved_chord, @machine, @context)
  end

  test "note_length shorter than 1.0 ends the note before the chord duration elapses" do
    resolved_chord = %ResolvedChord{
      root: :c,
      notes: [:c, :e, :g, :b],
      degree: :I,
      modifier: :maj7
    }

    machine = %RootNote{@machine | note_length: 0.5}

    assert [_note_on, %Event{type: :note_off, at_beat: 2.0}] =
             RootNote.generate(resolved_chord, machine, @context)
  end
end
