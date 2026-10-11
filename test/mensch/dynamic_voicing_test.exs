defmodule Mensch.DynamicVoicingTest do
  use ExUnit.Case, async: true

  alias Mensch.BeatPosition
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Harmony.Resolver
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

    chord_spec = %ChordSpec{
      voicing: %ChordSpec.Voicing{},
      root: :c,
      tones: ["1", "3", "5", "7"],
      octave: 4,
      inversion: 0
    }

    machine = %DynamicVoicing{
      params: %DynamicVoicingParams{
        direction: :up,
        number_of_inversions: 0,
        modulation_strategy: DynamicVoicing.default_modulation_strategy()
      }
    }

    assert_raise ArgumentError, ~r/number_of_inversions must be >= 1/, fn ->
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])
    end
  end

  test "applies resolver-driven transitions at inversion boundaries" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 3000
    }

    chord_spec = %ChordSpec{
      voicing: %ChordSpec.Voicing{},
      root: :c,
      tones: ["1", "3", "5"],
      octave: 4,
      inversion: 0
    }

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: :up,
          number_of_inversions: 3,
          modulation_strategy: DynamicVoicing.default_modulation_strategy()
        }
      }

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    frame_0 = Enum.find(rendered.frames, &(&1.at_mbeat == 0))
    frame_1000 = Enum.find(rendered.frames, &(&1.at_mbeat == 1000))
    frame_2000 = Enum.find(rendered.frames, &(&1.at_mbeat == 2000))

    initial_voicing_count = chord_spec |> Resolver.resolve() |> length()

    assert Enum.count(frame_0.notes, & &1.note_on) == initial_voicing_count

    assert Enum.count(frame_1000.notes, & &1.note_on) >= 1
    assert Enum.count(frame_1000.notes, & &1.note_off) >= 1

    assert Enum.count(frame_2000.notes, & &1.note_on) >= 1
    assert Enum.count(frame_2000.notes, & &1.note_off) >= 1
  end

  test "all sounding notes end at chord duration" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 3000
    }

    chord_spec = %ChordSpec{
      voicing: %ChordSpec.Voicing{},
      root: :c,
      tones: ["1", "3", "5"],
      octave: 4,
      inversion: 0
    }

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: :down,
          number_of_inversions: 3,
          modulation_strategy: DynamicVoicing.default_modulation_strategy()
        }
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

  test "cycle_up direction bounces to top and back for one cycle" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 1000})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 5000
    }

    chord_spec = %ChordSpec{
      voicing: %ChordSpec.Voicing{},
      root: :c,
      tones: ["1", "3", "5"],
      octave: 4,
      inversion: 0
    }

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: {:cycle_up, 1},
          number_of_inversions: 3,
          modulation_strategy: DynamicVoicing.default_modulation_strategy()
        }
      }

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    expected_voicings =
      [0, 1, 2, 1, 0]
      |> Enum.map(fn inversion ->
        chord_spec
        |> Map.put(:inversion, inversion)
        |> Resolver.resolve()
        |> Enum.sort()
      end)

    assert_active_voicings_match(rendered.frames, expected_voicings)
  end

  test "cycle_down direction bounces for configured cycle count" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 1000})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 5000
    }

    chord_spec = %ChordSpec{
      voicing: %ChordSpec.Voicing{},
      root: :c,
      tones: ["1", "3", "5"],
      octave: 4,
      inversion: 0
    }

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: {:cycle_down, 2},
          number_of_inversions: 2,
          modulation_strategy: DynamicVoicing.default_modulation_strategy()
        }
      }

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    expected_voicings =
      [0, -1, 0, -1, 0]
      |> Enum.map(fn inversion ->
        chord_spec
        |> Map.put(:inversion, inversion)
        |> Resolver.resolve()
        |> Enum.sort()
      end)

    assert_active_voicings_match(rendered.frames, expected_voicings)
  end

  test "cycle modes fail validation when requested voicings exceed frame budget" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{
      voicing: %ChordSpec.Voicing{},
      root: :c,
      tones: ["1", "3", "5"],
      octave: 4,
      inversion: 0
    }

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: {:cycle_up, 2},
          number_of_inversions: 24,
          modulation_strategy: DynamicVoicing.default_modulation_strategy()
        }
      }

    assert_raise ArgumentError, ~r/requested .* voicings but only .* frame slots/, fn ->
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])
    end
  end

  test "pressure envelope rises and decays across the note lifecycle" do
    machine = %DynamicVoicing{
      params: %DynamicVoicingParams{
        direction: :up,
        number_of_inversions: 1,
        modulation_strategy: DynamicVoicing.default_modulation_strategy()
      }
    }

    pressures = pressures_by_at_mbeat(machine)
    pressure_values = Map.values(pressures)

    assert map_size(pressures) > 1
    assert Enum.min(pressure_values) < Enum.max(pressure_values)
  end

  defp assert_active_voicings_match(frames, expected_voicings) do
    active_by_mbeat = active_notes_by_mbeat(frames)

    expected_voicings
    |> Enum.with_index()
    |> Enum.each(fn {expected, index} ->
      mbeat = index * 1000
      assert Map.fetch!(active_by_mbeat, mbeat) == expected
    end)
  end

  defp active_notes_by_mbeat(frames) do
    {_, by_mbeat} =
      Enum.reduce(frames, {MapSet.new(), %{}}, fn frame, {active, acc} ->
        active_after_offs =
          Enum.reduce(frame.notes, active, fn note, active_acc ->
            if note.note_off, do: MapSet.delete(active_acc, note.midi_note), else: active_acc
          end)

        active_after_ons =
          Enum.reduce(frame.notes, active_after_offs, fn note, active_acc ->
            if note.note_on, do: MapSet.put(active_acc, note.midi_note), else: active_acc
          end)

        {active_after_ons,
         Map.put(acc, frame.at_mbeat, active_after_ons |> MapSet.to_list() |> Enum.sort())}
      end)

    by_mbeat
  end

  defp pressures_by_at_mbeat(machine, start_mbeat \\ 0) do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 500})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: start_mbeat},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{
      voicing: %ChordSpec.Voicing{},
      root: :c,
      tones: ["1", "3", "5"],
      octave: 4,
      inversion: 0
    }

    rendered =
      Machine.build_frame_sequence(
        machine,
        chord_spec,
        sample_context,
        timeline_context,
        absolute_chord_start_mbeat: start_mbeat
      )

    pressures =
      rendered.frames
      |> Enum.reduce(%{}, fn frame, acc ->
        pressure =
          frame.notes
          |> Enum.filter(&(&1.midi_note == 60))
          |> Enum.sort_by(& &1.note_instance_id)
          |> case do
            [note | _] -> note.pressure
            [] -> nil
          end

        if pressure == nil do
          acc
        else
          Map.put(acc, frame.at_mbeat, pressure)
        end
      end)

    assert map_size(pressures) > 0
    pressures
  end
end
