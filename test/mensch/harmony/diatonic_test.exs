defmodule Mensch.Harmony.DiatonicTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.Diatonic

  test "major ii only allows the minor-7 family" do
    assert Diatonic.valid_modifiers(:major, :ii) |> Enum.sort() ==
             Enum.sort([:min7, :min9, :min11, :min13])
  end

  test "major V only allows the dominant-7 family" do
    assert Diatonic.valid_modifiers(:major, :V) |> Enum.sort() ==
             Enum.sort([:dom7, :dom9, :dom11, :dom13])
  end

  test "major I only allows the major-7 family" do
    assert Diatonic.valid_modifiers(:major, :I) |> Enum.sort() ==
             Enum.sort([:maj7, :maj9, :maj11, :maj13])
  end

  test "major vii only allows the half-diminished 7th (no diatonic 9/11/13 exists)" do
    assert Diatonic.valid_modifiers(:major, :vii) == [:m7b5]
  end

  test "major iii only allows the plain minor 7th (its 9th is not diatonic)" do
    assert Diatonic.valid_modifiers(:major, :iii) == [:min7]
  end

  test "minor i allows the minor 7th plus its diatonic 9th and 11th (but not the 13th)" do
    assert Diatonic.valid_modifiers(:minor, :i) |> Enum.sort() ==
             Enum.sort([:min7, :min9, :min11])
  end
end
