defmodule Mensch.NewModulationTest do
  use ExUnit.Case, async: true

  alias Mensch.NewModulation
  alias Mensch.NewModulation.Lfo
  alias Mensch.NewModulation.LfoCurve
  alias Mensch.NewModulation.LfoGroup
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
        time_base: :chord
      }

    value = Lfo.evaluate(curve, 1000, sample_context, 0, 1000)

    assert_in_delta value, 0.5, 1.0e-6
  end

  test "lfo_group evaluates operations left-to-right" do
    sample_context = SampleContext.new!(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 50})

    group =
      %LfoGroup{
        initial: %LfoCurve{curve: :square, scale: 2.0, time_base: :chord},
        operations: [
          {:multiply, %LfoCurve{curve: :square, scale: 3.0, time_base: :chord}},
          {:add, %LfoCurve{curve: :square, scale: 4.0, time_base: :chord}}
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
        initial: %LfoCurve{curve: :square, scale: 2.0, time_base: :chord},
        operations: [{:add, %LfoCurve{curve: :square, scale: 1.0, time_base: :chord}}]
      }

    outer =
      %LfoGroup{
        initial: inner,
        operations: [{:multiply, %LfoCurve{curve: :square, scale: 3.0, time_base: :chord}}]
      }

    # ((2 + 1) * 3)
    value = Lfo.evaluate(outer, 0, sample_context, 0, 0)

    assert value == 9.0
  end

  test "apply_to_pressure clamps and rounds for add and multiply" do
    assert NewModulation.apply_to_pressure(80, 2.6, :add) == 83
    assert NewModulation.apply_to_pressure(120, 20.0, :add) == 127
    assert NewModulation.apply_to_pressure(5, -20.0, :add) == 0

    assert NewModulation.apply_to_pressure(80, 0.1, :multiply) == 88
    assert NewModulation.apply_to_pressure(80, -1.0, :multiply) == 0
  end
end
