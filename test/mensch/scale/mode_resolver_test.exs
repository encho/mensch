defmodule Mensch.Scale.ModeResolverTest do
  use ExUnit.Case, async: true

  alias Mensch.Scale.ModeResolver

  test "major mode 1 is ionian" do
    assert {:ok, %{name: "Ionian", intervals: [0, 2, 4, 5, 7, 9, 11]}} =
             ModeResolver.resolve(:major, 1)
  end

  test "major mode 2 is dorian" do
    assert {:ok, %{name: "Dorian", intervals: [0, 2, 3, 5, 7, 9, 10]}} =
             ModeResolver.resolve(:major, 2)
  end

  test "major mode 6 is aeolian" do
    assert {:ok, %{name: "Aeolian", intervals: [0, 2, 3, 5, 7, 8, 10]}} =
             ModeResolver.resolve(:major, 6)
  end

  test "harmonic minor mode 5 is phrygian dominant" do
    assert {:ok, %{name: "Phrygian Dominant", intervals: [0, 1, 4, 5, 7, 8, 10]}} =
             ModeResolver.resolve(:harmonic_minor, 5)
  end

  test "melodic minor mode 4 is lydian dominant" do
    assert {:ok, %{name: "Lydian Dominant", intervals: [0, 2, 4, 6, 7, 9, 10]}} =
             ModeResolver.resolve(:melodic_minor, 4)
  end

  test "harmonic major mode 1" do
    assert {:ok, %{name: "Harmonic Major", intervals: [0, 2, 4, 5, 7, 8, 11]}} =
             ModeResolver.resolve(:harmonic_major, 1)
  end

  test "all resolved modes start at zero and are unique" do
    for family <- [:major, :harmonic_minor, :melodic_minor, :harmonic_major],
        mode <- 1..7 do
      assert {:ok, %{intervals: intervals}} = ModeResolver.resolve(family, mode)
      assert Enum.at(intervals, 0) == 0
      assert Enum.uniq(intervals) == intervals
      assert length(intervals) == 7
    end
  end
end
