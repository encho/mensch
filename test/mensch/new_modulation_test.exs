defmodule Mensch.NewModulationTest do
  use ExUnit.Case, async: true

  alias Mensch.NewModulation
  alias Mensch.NewModulation.Lfo
  alias Mensch.NewModulation.LfoCurve
  alias Mensch.NewModulation.LfoGroup
  alias Mensch.NewModulation.LfoRamp
  alias Mensch.NewModulation.LfoSaw
  alias Mensch.SampleContext

  test "lfo_curve evaluates scaled sine value" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    curve =
      %LfoCurve{
        curve: :sine,
        scale: 0.5,
        cycles_per_bar: 1.0,
        shift_mbeats: 0.0,
        polarity: :bipolar,
        anchor: :chord
      }

    value = Lfo.evaluate(curve, 1000, sample_context, 0, 1000)

    assert_in_delta value, 0.5, 1.0e-6
  end

  test "lfo_group evaluates operations left-to-right" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    group =
      %LfoGroup{
        initial: %LfoCurve{curve: :square, scale: 2.0, anchor: :chord},
        operations: [
          {:multiply, %LfoCurve{curve: :square, scale: 3.0, anchor: :chord}},
          {:add, %LfoCurve{curve: :square, scale: 4.0, anchor: :chord}}
        ]
      }

    # ((2 * 3) + 4) at cycle phase where square = +1.
    value = Lfo.evaluate(group, 0, sample_context, 0, 0)

    assert value == 10.0
  end

  test "lfo_group supports nested groups" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    inner =
      %LfoGroup{
        initial: %LfoCurve{curve: :square, scale: 2.0, anchor: :chord},
        operations: [{:add, %LfoCurve{curve: :square, scale: 1.0, anchor: :chord}}]
      }

    outer =
      %LfoGroup{
        initial: inner,
        operations: [{:multiply, %LfoCurve{curve: :square, scale: 3.0, anchor: :chord}}]
      }

    # ((2 + 1) * 3)
    value = Lfo.evaluate(outer, 0, sample_context, 0, 0)

    assert value == 9.0
  end

  test "lfo_saw drop_phase controls when reset happens" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    saw =
      %LfoSaw{
        curve: :saw_up,
        scale: 1.0,
        cycles_per_bar: 1.0,
        shift_mbeats: 0.0,
        polarity: :bipolar,
        anchor: :chord,
        drop_phase: 0.5
      }

    # at 1000 mbeat of a 4000 mbeat bar: cycle_phase = 0.25 -> 0.25 / 0.5 = 0.5
    assert_in_delta Lfo.evaluate(saw, 1000, sample_context, 0, 1000), 0.5, 1.0e-6

    # at 3000 mbeat: cycle_phase = 0.75 >= 0.5, so it has already dropped.
    assert Lfo.evaluate(saw, 3000, sample_context, 0, 3000) == 0.0
  end

  test "lfo_group normalizes saw term maps via drop_phase key" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    group =
      %LfoGroup{
        initial: %{curve: :saw_up, scale: 1.0, drop_phase: 0.5, anchor: :chord},
        operations: []
      }

    assert_in_delta Lfo.evaluate(group, 1000, sample_context, 0, 1000), 0.5, 1.0e-6
  end

  test "lfo_ramp is non-cyclic and holds final value" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    ramp =
      %LfoRamp{
        start_value: 0.0,
        end_value: 1.0,
        interpolation_function: :linear,
        span_mbeats: 2000.0,
        shift_mbeats: 0.0,
        anchor: :chord
      }

    # progress = 0.5 at 1000/2000
    assert_in_delta Lfo.evaluate(ramp, 1000, sample_context, 0, 1000), 0.5, 1.0e-6
    # progress clamps at 1.0 and stays there (no wrap)
    assert_in_delta Lfo.evaluate(ramp, 3000, sample_context, 0, 3000), 1.0, 1.0e-6
  end

  test "lfo_group normalizes ramp term maps via span_mbeats key" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    group =
      %LfoGroup{
        initial: %{
          start_value: 0.0,
          end_value: 1.0,
          interpolation_function: :linear,
          span_mbeats: 2000.0,
          anchor: :chord
        },
        operations: []
      }

    assert_in_delta Lfo.evaluate(group, 1000, sample_context, 0, 1000), 0.5, 1.0e-6
    assert_in_delta Lfo.evaluate(group, 3000, sample_context, 0, 3000), 1.0, 1.0e-6
  end

  test "lfo_ramp positive shift_mbeats delays start" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    ramp =
      %LfoRamp{
        start_value: 0.0,
        end_value: 1.0,
        interpolation_function: :linear,
        span_mbeats: 2000.0,
        shift_mbeats: 1000.0,
        anchor: :chord
      }

    # Ramp starts 1000 mbeats later, so at 500 we're still at the start.
    assert_in_delta Lfo.evaluate(ramp, 500, sample_context, 0, 500), 0.0, 1.0e-6
    # At 1500, effective progress is (1500 - 1000) / 2000 = 0.25.
    assert_in_delta Lfo.evaluate(ramp, 1500, sample_context, 0, 1500), 0.25, 1.0e-6
  end

  test "apply_to_pressure clamps and rounds for add and multiply" do
    assert NewModulation.apply_to_pressure(80, 2.6, :add) == 83
    assert NewModulation.apply_to_pressure(120, 20.0, :add) == 127
    assert NewModulation.apply_to_pressure(5, -20.0, :add) == 0

    assert NewModulation.apply_to_pressure(80, 0.1, :multiply) == 88
    assert NewModulation.apply_to_pressure(80, -1.0, :multiply) == 0
  end
end
