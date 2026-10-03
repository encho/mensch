defmodule Mensch.StrumTest do
  use ExUnit.Case, async: true

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machine
  alias Mensch.Machines.Strum
  alias Mensch.Machines.StrumParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  test "plays all chord notes together from chord start to end" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    machine = %Strum{params: StrumParams.default()}

    rendered =
      Machine.build_frame_sequence(
        machine,
        chord_spec,
        sample_context,
        timeline_context,
        []
      )

    expected_notes = ChordSpec.to_midi_notes(chord_spec)

    frame_0 = Enum.find(rendered.frames, &(&1.at_mbeat == 0))
    frame_end = Enum.find(rendered.frames, &(&1.at_mbeat == 4000))

    note_ons =
      frame_0.notes
      |> Enum.filter(& &1.note_on)
      |> Enum.map(& &1.midi_note)
      |> Enum.sort()

    note_offs =
      frame_end.notes
      |> Enum.filter(& &1.note_off)
      |> Enum.map(& &1.midi_note)
      |> Enum.sort()

    assert note_ons == expected_notes
    assert note_offs == expected_notes
  end
end
