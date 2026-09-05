defmodule Mensch.Harmony.ResolverTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.{ChordSpec, Key, Resolver, ResolvedChord}

  @c_major %Key{root: :c, scale: :major}

  test "C major + ii + min7 => Dm7" do
    assert Resolver.resolve(@c_major, %ChordSpec{degree: :ii, modifier: :min7}) ==
             %ResolvedChord{root: :d, notes: [:d, :f, :a, :c], degree: :ii, modifier: :min7}
  end

  test "C major + V + dom7 => G7" do
    assert Resolver.resolve(@c_major, %ChordSpec{degree: :V, modifier: :dom7}) ==
             %ResolvedChord{root: :g, notes: [:g, :b, :d, :f], degree: :V, modifier: :dom7}
  end

  test "C major + I + maj7 => Cmaj7" do
    assert Resolver.resolve(@c_major, %ChordSpec{degree: :I, modifier: :maj7}) ==
             %ResolvedChord{root: :c, notes: [:c, :e, :g, :b], degree: :I, modifier: :maj7}
  end
end
