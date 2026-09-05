defmodule Mensch.Harmony.ScaleTest do
  use ExUnit.Case, async: true

  alias Mensch.Harmony.Scale

  test "roman_numeral/2 cases degrees correctly for the major mode" do
    assert Scale.roman_numeral(:major, :I) == "I"
    assert Scale.roman_numeral(:major, :ii) == "ii"
    assert Scale.roman_numeral(:major, :iii) == "iii"
    assert Scale.roman_numeral(:major, :IV) == "IV"
    assert Scale.roman_numeral(:major, :V) == "V"
    assert Scale.roman_numeral(:major, :vi) == "vi"
    assert Scale.roman_numeral(:major, :vii) == "vii"
  end

  test "roman_numeral/2 cases degrees correctly for the minor mode" do
    assert Scale.roman_numeral(:minor, :I) == "i"
    assert Scale.roman_numeral(:minor, :ii) == "ii"
    assert Scale.roman_numeral(:minor, :IV) == "iv"
    assert Scale.roman_numeral(:minor, :V) == "v"
    assert Scale.roman_numeral(:minor, :vi) == "VI"
    assert Scale.roman_numeral(:minor, :vii) == "VII"
  end

  test "note_at_degree/2 resolves the ii of C major to D" do
    assert Scale.note_at_degree(%Scale{key: :c, mode: :major}, :ii) == :d
  end

  test "note_at_degree/2 resolves the VII of C minor to Bb" do
    assert Scale.note_at_degree(%Scale{key: :c, mode: :minor}, :vii) == :a_sharp
  end
end
