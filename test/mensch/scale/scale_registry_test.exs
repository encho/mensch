defmodule Mensch.Scale.ScaleRegistryTest do
  use ExUnit.Case, async: true

  alias Mensch.Scale.ScaleRegistry

  test "registers four modal families" do
    families = ScaleRegistry.families()

    assert length(families) == 4
    assert Enum.any?(families, &(&1.id == :major))
    assert Enum.any?(families, &(&1.id == :harmonic_minor))
    assert Enum.any?(families, &(&1.id == :melodic_minor))
    assert Enum.any?(families, &(&1.id == :harmonic_major))

    assert Enum.all?(families, fn family -> map_size(family.mode_names) == 7 end)
  end

  test "registers seven standalone scales" do
    standalones = ScaleRegistry.standalone_scales()

    assert length(standalones) == 7
    assert Enum.any?(standalones, &(&1.id == :major_pentatonic))
    assert Enum.any?(standalones, &(&1.id == :minor_pentatonic))
    assert Enum.any?(standalones, &(&1.id == :minor_blues))
    assert Enum.any?(standalones, &(&1.id == :whole_tone))
    assert Enum.any?(standalones, &(&1.id == :half_whole_diminished))
    assert Enum.any?(standalones, &(&1.id == :whole_half_diminished))
    assert Enum.any?(standalones, &(&1.id == :double_harmonic_major))
  end

  test "invalid family identifiers return controlled errors" do
    assert {:error, :unknown_scale_family} = ScaleRegistry.fetch(:unknown)
  end
end
