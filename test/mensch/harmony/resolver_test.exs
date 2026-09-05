defmodule Mensch.Harmony.ResolverTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.{ChordSpec, Resolver, ResolvedChord, Scale}

  @c_major %Scale{key: :c, mode: :major}

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

  test "C major + ii + min9 => Dm9" do
    assert Resolver.resolve(@c_major, %ChordSpec{degree: :ii, modifier: :min9}) ==
             %ResolvedChord{root: :d, notes: [:d, :f, :a, :c, :e], degree: :ii, modifier: :min9}
  end
end
