defmodule Mensch.SampleContextTest do
  use ExUnit.Case, async: true

  alias Mensch.SampleContext
  alias Mensch.SampleDb

  test "accepts frame_mbeats values that divide one beat" do
    valid_steps = [1, 5, 10, 20, 25, 40, 50, 100, 125, 200, 250, 500, 1000]

    for frame_mbeats <- valid_steps do
      assert {:ok, %SampleContext{frame_mbeats: ^frame_mbeats}} =
               SampleContext.new(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: frame_mbeats})
    end
  end

  test "rejects frame_mbeats values that do not divide one beat" do
    assert {:error, {:frame_mbeats_must_divide_beat, 60}} =
             SampleContext.new(%{bpm: 120, time_signature: {4, 4}, frame_mbeats: 60})
  end

  test "all built-in sample contexts are valid" do
    assert Enum.all?(SampleDb.default_samples(), fn sample ->
             match?({:ok, _}, SampleContext.validate(sample.sample_context))
           end)
  end
end
