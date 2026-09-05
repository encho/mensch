defmodule Mensch.TempoTest do
  # Exercises the shared global GenServer (bpm/0, set_bpm/1), so this
  # must not run concurrently with other tests touching global tempo.
  use ExUnit.Case, async: false

  alias Mensch.Tempo

  setup do
    original_bpm = Tempo.bpm()
    on_exit(fn -> Tempo.set_bpm(original_bpm) end)
    :ok
  end

  test "defaults to 120 bpm" do
    assert Tempo.bpm() == 120
  end

  test "set_bpm/1 updates the global bpm" do
    assert Tempo.set_bpm(90) == :ok
    assert Tempo.bpm() == 90
  end

  test "beats_per_bar/0 is 4 (4/4 time)" do
    assert Tempo.beats_per_bar() == 4
  end

  test "beat_duration_ms/1 and bar_duration_ms/1 are pure functions of bpm" do
    assert Tempo.beat_duration_ms(120) == 500.0
    assert Tempo.bar_duration_ms(120) == 2000.0
    assert Tempo.beat_duration_ms(60) == 1000.0
    assert Tempo.bar_duration_ms(60) == 4000.0
  end

  test "bars_to_ms/2 converts bars to milliseconds at a given bpm" do
    assert Tempo.bars_to_ms(1, 120) == 2000
    assert Tempo.bars_to_ms(4, 120) == 8000
    assert Tempo.bars_to_ms(0.5, 120) == 1000
    assert Tempo.bars_to_ms(0, 120) == 0
  end

  test "bars_to_ms/1 uses the current global bpm" do
    Tempo.set_bpm(120)
    assert Tempo.bars_to_ms(2) == 4000
  end
end
