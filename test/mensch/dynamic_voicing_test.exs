defmodule Mensch.DynamicVoicingTest do
  use ExUnit.Case, async: true

  alias Mensch.BeatPosition
  alias Mensch.ChordSpec
  alias Mensch.Machine
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.Modulation.LfoCurve
  alias Mensch.Modulation.LfoGroup
  alias Mensch.Modulation.LfoSaw
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

  test "pressure LFO additive mode applies direct 7-bit modulation" do
    baseline_machine = baseline_lfo_machine()

    additive_machine =
      lfo_machine(%{
        lfo_pressure: %{
          lfo: %{
            curve: :square,
            scale: 1.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            time_base: :chord
          },
          mode: :add
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine)
    additive = pressures_by_at_mbeat(additive_machine)

    assert additive[1000] == expected_lfo_pressure(baseline[1000], 1.0, :add, 1.0)
    assert additive[3000] == expected_lfo_pressure(baseline[3000], -1.0, :add, 1.0)
  end

  test "pressure LFO multiplicative mode applies direct 7-bit modulation" do
    baseline_machine = baseline_lfo_machine()

    multiplicative_machine =
      lfo_machine(%{
        lfo_pressure: %{
          lfo: %{
            curve: :square,
            scale: 1.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            time_base: :chord
          },
          mode: :multiply
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine)
    multiplicative = pressures_by_at_mbeat(multiplicative_machine)

    assert multiplicative[1000] ==
             expected_lfo_pressure(baseline[1000], 1.0, :multiply, 1.0)

    assert multiplicative[3000] ==
             expected_lfo_pressure(baseline[3000], -1.0, :multiply, 1.0)
  end

  test "pressure LFO cycles-per-bar changes waveform speed" do
    baseline_machine = baseline_lfo_machine()

    one_cycle_machine =
      lfo_machine(%{
        lfo_pressure: %{
          lfo: %{
            curve: :saw_up,
            scale: 4.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            time_base: :chord
          },
          mode: :add
        }
      })

    two_cycle_machine =
      lfo_machine(%{
        lfo_pressure: %{
          lfo: %{
            curve: :saw_up,
            scale: 4.0,
            cycles_per_bar: 2.0,
            shift_mbeats: 0.0,
            time_base: :chord
          },
          mode: :add
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine)
    one_cycle = pressures_by_at_mbeat(one_cycle_machine)
    two_cycle = pressures_by_at_mbeat(two_cycle_machine)

    assert one_cycle[3000] == expected_lfo_pressure(baseline[3000], 0.75, :add, 4.0)
    assert two_cycle[3000] == expected_lfo_pressure(baseline[3000], 0.5, :add, 4.0)
    refute one_cycle[3000] == two_cycle[3000]
  end

  test "pressure LFO shift offsets waveform phase" do
    baseline_machine = baseline_lfo_machine()

    unshifted_machine =
      lfo_machine(%{
        lfo_pressure: %{
          lfo: %{
            curve: :saw_up,
            scale: 3.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            time_base: :chord
          },
          mode: :add
        }
      })

    shifted_machine =
      lfo_machine(%{
        lfo_pressure: %{
          lfo: %{
            curve: :saw_up,
            scale: 3.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 1000.0,
            time_base: :chord
          },
          mode: :add
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine)
    unshifted = pressures_by_at_mbeat(unshifted_machine)
    shifted = pressures_by_at_mbeat(shifted_machine)

    assert unshifted[3000] == expected_lfo_pressure(baseline[3000], 0.75, :add, 3.0)
    assert shifted[3000] == expected_lfo_pressure(baseline[3000], 0.0, :add, 3.0)
    refute shifted[3000] == unshifted[3000]
  end

  test "pressure LFO sample and chord time base differ for non-zero start" do
    baseline_machine = baseline_lfo_machine()

    absolute_machine =
      lfo_machine(%{
        lfo_pressure: %{
          lfo: %{
            curve: :saw_up,
            scale: 3.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            time_base: :sample
          },
          mode: :add
        }
      })

    chord_machine =
      lfo_machine(%{
        lfo_pressure: %{
          lfo: %{
            curve: :saw_up,
            scale: 3.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            time_base: :chord
          },
          mode: :add
        }
      })

    baseline = pressures_by_at_mbeat(baseline_machine, 1000)
    absolute_with_start_offset = pressures_by_at_mbeat(absolute_machine, 1000)
    chord_with_start_offset = pressures_by_at_mbeat(chord_machine, 1000)

    assert absolute_with_start_offset[3000] ==
             expected_lfo_pressure(baseline[3000], 0.0, :add, 3.0)

    assert chord_with_start_offset[3000] ==
             expected_lfo_pressure(baseline[3000], 0.75, :add, 3.0)

    refute absolute_with_start_offset[3000] == chord_with_start_offset[3000]
  end

  test "slide stays at baseline zero when lfo_slide is omitted" do
    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: :up,
          number_of_inversions: 1,
          lfo_pressure: %{lfo: zero_lfo_group(), mode: :add}
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
          lfo_pressure: %{lfo: zero_lfo_group(), mode: :add},
          lfo_slide: %{
            lfo: curve_group(:square, 0.0, 0.5, 1.0, 0.0, :chord),
            mode: :add
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

  test "bend stays at baseline zero when lfo_bend is omitted" do
    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: :up,
          number_of_inversions: 1,
          lfo_pressure: %{lfo: zero_lfo_group(), mode: :add}
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

    bends =
      rendered.frames
      |> Enum.flat_map(fn frame ->
        frame.notes
        |> Enum.filter(&(&1.midi_note == 60))
        |> Enum.map(& &1.bend)
      end)

    assert bends != []
    assert Enum.all?(bends, &(&1 == 0.0))
  end

  test "bend lfo applies additive bipolar modulation" do
    machine =
      %DynamicVoicing{
        params: %DynamicVoicingParams{
          direction: :up,
          number_of_inversions: 1,
          lfo_pressure: %{lfo: zero_lfo_group(), mode: :add},
          lfo_bend: %{
            lfo: curve_group(:square, -0.5, 0.5, 1.0, 0.0, :chord),
            mode: :add
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

    bends_by_mbeat =
      rendered.frames
      |> Enum.reduce(%{}, fn frame, acc ->
        bend =
          frame.notes
          |> Enum.filter(&(&1.midi_note == 60))
          |> Enum.sort_by(& &1.note_instance_id)
          |> case do
            [note | _] -> note.bend
            [] -> nil
          end

        if bend == nil do
          acc
        else
          Map.put(acc, frame.at_mbeat, bend)
        end
      end)

    assert bends_by_mbeat[1000] == 0.5
    assert bends_by_mbeat[3000] == -0.5
  end

  defp baseline_lfo_machine do
    lfo_machine(%{lfo_pressure: %{lfo: %{scale: 0.0}, mode: :add}})
  end

  defp lfo_machine(overrides) do
    base_params =
      %DynamicVoicingParams{
        direction: :up,
        number_of_inversions: 1,
        lfo_pressure: %{
          lfo: zero_lfo_group(),
          mode: :add
        }
      }

    merged_lfo_pressure =
      Map.merge(base_params.lfo_pressure, Map.get(overrides, :lfo_pressure, %{}))

    merged_lfo =
      merge_lfo_term(
        Map.get(base_params.lfo_pressure, :lfo),
        Map.get(merged_lfo_pressure, :lfo)
      )

    merged_lfo_pressure = Map.put(merged_lfo_pressure, :lfo, merged_lfo)

    params =
      base_params
      |> Map.from_struct()
      |> Map.merge(Map.drop(overrides, [:lfo_pressure]))
      |> Map.put(:lfo_pressure, merged_lfo_pressure)

    %DynamicVoicing{params: struct!(DynamicVoicingParams, params)}
  end

  defp merge_lfo_term(base_lfo, nil), do: base_lfo

  defp merge_lfo_term(base_lfo, override_lfo) when is_map(override_lfo) do
    if typed_lfo_struct?(override_lfo) do
      override_lfo
    else
      base_curve = lfo_curve_from_term(base_lfo)

      curve = Map.get(override_lfo, :curve, base_curve.curve)
      cycles_per_bar = Map.get(override_lfo, :cycles_per_bar, base_curve.cycles_per_bar)
      shift_mbeats = Map.get(override_lfo, :shift_mbeats, base_curve.shift_mbeats)

      anchor =
        Map.get(override_lfo, :time_base, Map.get(override_lfo, :anchor, base_curve.anchor))

      curve = normalize_curve(curve)

      {min_value, max_value} =
        case Map.fetch(override_lfo, :scale) do
          {:ok, scale} ->
            scale = scale * 1.0

            case Map.get(override_lfo, :polarity, :bipolar) do
              :unipolar -> {0.0, scale}
              _ -> {-scale, scale}
            end

          :error ->
            {
              Map.get(override_lfo, :min_value, base_curve.min_value),
              Map.get(override_lfo, :max_value, base_curve.max_value)
            }
        end

      case curve do
        saw when saw in [:saw, :saw_up, :saw_down] ->
          peak_value = max(abs(min_value), abs(max_value))

          polarity =
            if min_value == 0.0 and max_value >= 0.0, do: :unipolar, else: :bipolar

          saw_group(curve, peak_value, cycles_per_bar, shift_mbeats, polarity, anchor)

        _ ->
          curve_group(curve, min_value, max_value, cycles_per_bar, shift_mbeats, anchor)
      end
    end
  end

  defp typed_lfo_struct?(%LfoGroup{}), do: true
  defp typed_lfo_struct?(%LfoCurve{}), do: true
  defp typed_lfo_struct?(%LfoSaw{}), do: true
  defp typed_lfo_struct?(_), do: false

  defp lfo_curve_from_term(%LfoGroup{initial: %LfoCurve{} = curve}), do: curve
  defp lfo_curve_from_term(%LfoGroup{initial: %LfoSaw{}}), do: LfoCurve.default()
  defp lfo_curve_from_term(%LfoCurve{} = curve), do: curve

  defp curve_group(curve, min_value, max_value, cycles_per_bar, shift_mbeats, anchor) do
    %LfoGroup{
      initial: %LfoCurve{
        curve: curve,
        min_value: min_value * 1.0,
        max_value: max_value * 1.0,
        cycles_per_bar: cycles_per_bar * 1.0,
        shift_mbeats: shift_mbeats * 1.0,
        anchor: anchor
      },
      operations: []
    }
  end

  defp saw_group(curve, peak_value, cycles_per_bar, shift_mbeats, polarity, anchor) do
    %LfoGroup{
      initial: %LfoSaw{
        curve: curve,
        peak_value: peak_value * 1.0,
        cycles_per_bar: cycles_per_bar * 1.0,
        shift_mbeats: shift_mbeats * 1.0,
        polarity: polarity,
        anchor: anchor,
        drop_phase: 1.0
      },
      operations: []
    }
  end

  defp normalize_curve(:saw), do: :saw_up
  defp normalize_curve(curve), do: curve

  defp zero_lfo_group do
    curve_group(:sine, 0.0, 0.0, 1.0, 0.0, :sample)
  end

  defp expected_lfo_pressure(base_pressure, lfo_norm, mode, scale) do
    case mode do
      :add ->
        (base_pressure + lfo_norm * scale)
        |> round()
        |> min(127)
        |> max(0)

      :multiply ->
        (base_pressure * (1 + lfo_norm * scale))
        |> round()
        |> min(127)
        |> max(0)
    end
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
