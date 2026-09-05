defmodule Mensch.Performance.EngineTest do
  use ExUnit.Case, async: true

  alias Mensch.Performance.Engine
  alias Mensch.Performance.Event
  alias Mensch.Project

  test "generates the default project's timeline: ii7 -> V7 -> Imaj7, 4 beats each" do
    events = Engine.generate(Project.default())

    assert events == [
             %Event{type: :note_on, at_beat: 0.0, note: {:d, 3}, velocity: 90},
             %Event{type: :note_off, at_beat: 4.0, note: {:d, 3}},
             %Event{type: :note_on, at_beat: 4.0, note: {:g, 3}, velocity: 90},
             %Event{type: :note_off, at_beat: 8.0, note: {:g, 3}},
             %Event{type: :note_on, at_beat: 8.0, note: {:c, 3}, velocity: 90},
             %Event{type: :note_off, at_beat: 12.0, note: {:c, 3}}
           ]
  end

  test "chords start at index * chord_duration" do
    events = Engine.generate(Project.default())
    note_ons = Enum.filter(events, &(&1.type == :note_on))

    assert Enum.map(note_ons, & &1.at_beat) == [0.0, 4.0, 8.0]
  end

  test "the final note off lands at the end of the progression" do
    events = Engine.generate(Project.default())

    assert %Event{type: :note_off, at_beat: 12.0} = List.last(events)
  end
end
