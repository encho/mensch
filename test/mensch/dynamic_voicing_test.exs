defmodule Mensch.DynamicVoicingTest do
  use ExUnit.Case, async: true

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.LfoParams
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

  test "cycle_up direction bounces to top and back for one cycle" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 1000})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 5000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{direction: {:cycle_up, 1}, number_of_inversions: 3}
      }

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    boundary_note_ons = transition_note_ons_by_mbeat(rendered.frames)

    assert boundary_note_ons == %{1000 => 72, 2000 => 76, 3000 => 64, 4000 => 60}
  end

  test "cycle_down direction bounces for configured cycle count" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 1000})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 5000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{direction: {:cycle_down, 2}, number_of_inversions: 2}
      }

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    boundary_note_ons = transition_note_ons_by_mbeat(rendered.frames)

    assert boundary_note_ons == %{1000 => 55, 2000 => 67, 3000 => 55, 4000 => 67}
  end

  test "cycle modes fail validation when requested voicings exceed frame budget" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{direction: {:cycle_up, 2}, number_of_inversions: 24}
      }

    assert_raise ArgumentError, ~r/requested .* voicings but only .* frame slots/, fn ->
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])
    end
  end

  test "pressure LFO additive mode applies adsr-scaled modulation" do
    baseline_machine = baseline_lfo_machine()

    additive_machine =
      lfo_machine(%{
        lfo_pressure: %{
          curve: :square,
          scale: 1.0,
          cycles_per_bar: 1.0,
          shift_mbeats: 0.0,
          time_base: :entry_local,
          mode: :additive
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine)
    additive = pressures_by_at_mbeat(additive_machine)

    assert additive[1000] == expected_lfo_pressure(baseline[1000], 1.0, :additive, 1.0)
    assert additive[3000] == expected_lfo_pressure(baseline[3000], -1.0, :additive, 1.0)
  end

  test "pressure LFO multiplicative mode applies adsr-scaled modulation" do
    baseline_machine = baseline_lfo_machine()

    multiplicative_machine =
      lfo_machine(%{
        lfo_pressure: %{
          curve: :square,
          scale: 1.0,
          cycles_per_bar: 1.0,
          shift_mbeats: 0.0,
          time_base: :entry_local,
          mode: :multiplicative
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine)
    multiplicative = pressures_by_at_mbeat(multiplicative_machine)

    assert multiplicative[1000] ==
             expected_lfo_pressure(baseline[1000], 1.0, :multiplicative, 1.0)

    assert multiplicative[3000] ==
             expected_lfo_pressure(baseline[3000], -1.0, :multiplicative, 1.0)
  end

  test "pressure LFO cycles-per-bar changes waveform speed" do
    baseline_machine = baseline_lfo_machine()

    one_cycle_machine =
      lfo_machine(%{
        lfo_pressure: %{
          curve: :saw_up,
          scale: 0.25,
          cycles_per_bar: 1.0,
          shift_mbeats: 0.0,
          time_base: :entry_local,
          mode: :additive
        }
      })

    two_cycle_machine =
      lfo_machine(%{
        lfo_pressure: %{
          curve: :saw_up,
          scale: 0.25,
          cycles_per_bar: 2.0,
          shift_mbeats: 0.0,
          time_base: :entry_local,
          mode: :additive
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine)
    one_cycle = pressures_by_at_mbeat(one_cycle_machine)
    two_cycle = pressures_by_at_mbeat(two_cycle_machine)

    assert one_cycle[3000] == expected_lfo_pressure(baseline[3000], 0.75, :additive, 0.25)
    assert two_cycle[3000] == expected_lfo_pressure(baseline[3000], 0.5, :additive, 0.25)
    refute one_cycle[3000] == two_cycle[3000]
  end

  test "pressure LFO shift offsets waveform phase" do
    baseline_machine = baseline_lfo_machine()

    unshifted_machine =
      lfo_machine(%{
        lfo_pressure: %{
          curve: :saw_up,
          scale: 0.5,
          cycles_per_bar: 1.0,
          shift_mbeats: 0.0,
          time_base: :entry_local,
          mode: :additive
        }
      })

    shifted_machine =
      lfo_machine(%{
        lfo_pressure: %{
          curve: :saw_up,
          scale: 0.5,
          cycles_per_bar: 1.0,
          shift_mbeats: 1000.0,
          time_base: :entry_local,
          mode: :additive
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine)
    unshifted = pressures_by_at_mbeat(unshifted_machine)
    shifted = pressures_by_at_mbeat(shifted_machine)

    assert unshifted[3000] == expected_lfo_pressure(baseline[3000], 0.75, :additive, 0.5)
    assert shifted[3000] == expected_lfo_pressure(baseline[3000], 0.0, :additive, 0.5)
    refute shifted[3000] == unshifted[3000]
  end

  test "pressure LFO absolute and entry-local time base differ for non-zero start" do
    baseline_machine = baseline_lfo_machine()

    absolute_machine =
      lfo_machine(%{
        lfo_pressure: %{
          curve: :saw_up,
          scale: 0.5,
          cycles_per_bar: 1.0,
          shift_mbeats: 0.0,
          time_base: :absolute,
          mode: :additive
        }
      })

    entry_local_machine =
      lfo_machine(%{
        lfo_pressure: %{
          curve: :saw_up,
          scale: 0.5,
          cycles_per_bar: 1.0,
          shift_mbeats: 0.0,
          time_base: :entry_local,
          mode: :additive
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine, 1000)
    absolute_with_start_offset = pressures_by_at_mbeat(absolute_machine, 1000)
    entry_local_with_start_offset = pressures_by_at_mbeat(entry_local_machine, 1000)

    assert absolute_with_start_offset[3000] ==
             expected_lfo_pressure(baseline[3000], 0.0, :additive, 0.5)

    assert entry_local_with_start_offset[3000] ==
             expected_lfo_pressure(baseline[3000], 0.75, :additive, 0.5)

    refute absolute_with_start_offset[3000] == entry_local_with_start_offset[3000]
  end

  test "slide stays at baseline zero when lfo_slide is omitted" do
    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: :up,
          number_of_inversions: 1,
          lfo_pressure: %{scale: 0.0}
        }
      }

    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 500})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    slides =
      rendered.frames
      |> Enum.flat_map(fn frame ->
        frame.notes
        |> Enum.filter(&(&1.midi_note == 60))
        |> Enum.map(& &1.slide)
      end)

    assert slides != []
    assert Enum.all?(slides, &(&1 == 0))
  end

  test "slide lfo applies additive unipolar modulation" do
    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: :up,
          number_of_inversions: 1,
          lfo_pressure: %{scale: 0.0},
          lfo_slide: %{
            curve: :square,
            scale: 0.5,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            polarity: :unipolar,
            time_base: :entry_local,
            mode: :additive
          }
        }
      }

    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 500})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: 0},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    rendered =
      Machine.build_frame_sequence(machine, chord_spec, sample_context, timeline_context, [])

    slides_by_mbeat =
      rendered.frames
      |> Enum.reduce(%{}, fn frame, acc ->
        slide =
          frame.notes
          |> Enum.filter(&(&1.midi_note == 60))
          |> Enum.sort_by(& &1.note_instance_id)
          |> case do
            [note | _] -> note.slide
            [] -> nil
          end

        if slide == nil do
          acc
        else
          Map.put(acc, frame.at_mbeat, slide)
        end
      end)

    assert slides_by_mbeat[1000] == 64
    assert slides_by_mbeat[3000] == 0
  end

  defp baseline_lfo_machine do
    lfo_machine(%{lfo_pressure: %{scale: 0.0}})
  end

  defp lfo_machine(overrides) do
    base_params =
      %DynamicVoicingParams{
        direction: :up,
        number_of_inversions: 1,
        lfo_pressure: %LfoParams{
          curve: :sine,
          scale: 0.0,
          cycles_per_bar: 1.0,
          shift_mbeats: 0.0,
          time_base: :absolute,
          mode: :additive
        }
      }

    merged_lfo_pressure =
      base_params.lfo_pressure
      |> Map.from_struct()
      |> Map.merge(Map.get(overrides, :lfo_pressure, %{}))
      |> then(&struct!(LfoParams, &1))

    params =
      base_params
      |> Map.from_struct()
      |> Map.merge(Map.drop(overrides, [:lfo_pressure]))
      |> Map.put(:lfo_pressure, merged_lfo_pressure)

    %DynamicVoicing{params: struct!(DynamicVoicingParams, params)}
  end

  defp expected_lfo_pressure(base_pressure, lfo_norm, mode, scale) do
    adsr_level = base_pressure / 127

    normalized =
      case mode do
        :additive -> adsr_level + lfo_norm * adsr_level * scale
        :multiplicative -> adsr_level * (1 + lfo_norm * adsr_level * scale)
      end

    normalized
    |> Kernel.*(127)
    |> round()
    |> min(127)
    |> max(0)
  end

  defp transition_note_ons_by_mbeat(frames) do
    frames
    |> Enum.reduce(%{}, fn frame, acc ->
      note_ons = Enum.filter(frame.notes, & &1.note_on)

      case note_ons do
        [note] when frame.at_mbeat > 0 ->
          Map.put(acc, frame.at_mbeat, note.midi_note)

        _ ->
          acc
      end
    end)
  end

  defp pressures_by_at_mbeat(machine, start_mbeat \\ 0) do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 500})

    timeline_context = %TimelineContext{
      start_beat: %BeatPosition{bar: 0, beat: 0, mbeat: start_mbeat},
      duration_mbeats: 4000
    }

    chord_spec = %ChordSpec{root: :c, modifier: :maj, octave: 4, inversion: 0}

    rendered =
      Machine.build_frame_sequence(
        machine,
        chord_spec,
        sample_context,
        timeline_context,
        entry_start_mbeat_abs: start_mbeat
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
