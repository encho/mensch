defmodule Mensch.Machine.RootNoteMpeTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.ResolvedChord
  alias Mensch.Machine.RootNoteMpe
  alias Mensch.Performance.Event

  @resolved_chord %ResolvedChord{root: :d, notes: [:d, :f, :a, :c], degree: :ii, modifier: :min7}
  @context %{start_beat: 0.0, duration_beats: 4.0}

  test "plays the root note, like ROOT_NOTE" do
    machine = %RootNoteMpe{octave: 3, velocity: 90, note_length: 1.0, modulation_steps: 2}

    events = RootNoteMpe.generate(@resolved_chord, machine, @context)

    assert [%Event{type: :note_on, note: {:d, 3}, velocity: 90} = note_on | _rest] = events
    assert note_on.at_beat == 0.0

    assert %Event{type: :note_off, note: {:d, 3}} = note_off = List.last(events)
    assert note_off.at_beat == 4.0
  end

  test "emits pressure and pitch bend events between note on and note off" do
    machine = %RootNoteMpe{
      octave: 3,
      velocity: 90,
      note_length: 1.0,
      pressure_depth: 1.0,
      pitch_bend_depth: 2.0,
      modulation_steps: 4,
      modulation_cycles: 1
    }

    events = RootNoteMpe.generate(@resolved_chord, machine, @context)

    assert [%Event{type: :note_on}, %Event{type: :note_off}] =
             Enum.filter(events, &(&1.type in [:note_on, :note_off]))

    pressure_events = Enum.filter(events, &(&1.type == :pressure))
    pitch_bend_events = Enum.filter(events, &(&1.type == :pitch_bend))

    assert length(pressure_events) == 3
    assert length(pitch_bend_events) == 3
    assert Enum.all?(pressure_events, &(&1.note == {:d, 3}))
    assert Enum.all?(pressure_events, &(&1.value >= 0.0 and &1.value <= machine.pressure_depth))

    assert Enum.all?(
             pitch_bend_events,
             &(&1.value >= -machine.pitch_bend_depth and &1.value <= machine.pitch_bend_depth)
           )

    assert Enum.any?(pitch_bend_events, &(&1.value < 0.0))
    assert Enum.any?(pitch_bend_events, &(&1.value > 0.0))

    assert Enum.all?(events, &(&1.at_beat >= 0.0 and &1.at_beat <= 4.0))
  end

  test "no expression events when modulation_steps is below 2" do
    machine = %RootNoteMpe{modulation_steps: 1}
    events = RootNoteMpe.generate(@resolved_chord, machine, @context)

    assert [%Event{type: :note_on}, %Event{type: :note_off}] = events
  end
end
