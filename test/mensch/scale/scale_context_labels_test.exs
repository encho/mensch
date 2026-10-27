defmodule Mensch.ScaleContextLabelsTest do
  use ExUnit.Case, async: true

  alias Mensch.Scale

  @major_mode_expectations %{
    1 => "C Major",
    2 => "Bb Major",
    3 => "Ab Major",
    4 => "G Major",
    5 => "F Major",
    6 => "Eb Major",
    7 => "Db Major"
  }

  @harmonic_minor_mode_expectations %{
    1 => "C Harmonic Minor",
    2 => "Bb Harmonic Minor",
    3 => "A Harmonic Minor",
    4 => "G Harmonic Minor",
    5 => "F Harmonic Minor",
    6 => "E Harmonic Minor",
    7 => "Db Harmonic Minor"
  }

  test "builds explicit modal and parent labels for eb harmonic minor mode 6" do
    {:ok, scale_spec} = Scale.build_scale(:e_flat, :harmonic_minor, 6)

    labels = Scale.context_labels(scale_spec)

    assert labels.scale == "Eb Lydian #2 (Harmonic Minor Mode 6)"
    assert labels.parent_scale == "G Harmonic Minor"
  end

  test "builds parent label with flat preference for flat tonics" do
    {:ok, scale_spec} = Scale.build_scale(:d_flat, :major, 2)

    labels = Scale.context_labels(scale_spec)

    assert labels.scale == "Db Dorian (Major Mode 2)"
    assert labels.parent_scale == "Cb Major"
  end

  test "major-family parent labels are context-aware across all modes" do
    Enum.each(1..7, fn mode ->
      {:ok, scale_spec} = Scale.build_scale(:c, :major, mode)
      labels = Scale.context_labels(scale_spec)

      assert labels.parent_scale == Map.fetch!(@major_mode_expectations, mode)
    end)
  end

  test "harmonic-minor-family parent labels are context-aware across all modes" do
    Enum.each(1..7, fn mode ->
      {:ok, scale_spec} = Scale.build_scale(:c, :harmonic_minor, mode)
      labels = Scale.context_labels(scale_spec)

      assert labels.parent_scale == Map.fetch!(@harmonic_minor_mode_expectations, mode)
    end)
  end

  test "practical and strict modes keep parent pitch identity while adapting spelling" do
    {:ok, scale_spec} = Scale.build_scale(:e_flat, :harmonic_minor, 6)

    practical = Scale.context_labels(scale_spec, spelling_mode: :practical)
    strict = Scale.context_labels(scale_spec, spelling_mode: :strict)

    assert practical.parent_scale == "G Harmonic Minor"
    assert strict.parent_scale == "G Harmonic Minor"
  end

  test "c locrian and c phrygian parent labels avoid sharp-biased enharmonics" do
    {:ok, locrian_spec} = Scale.build_scale(:c, :major, 7)
    {:ok, phrygian_spec} = Scale.build_scale(:c, :major, 3)

    locrian_labels = Scale.context_labels(locrian_spec, spelling_mode: :practical)
    phrygian_labels = Scale.context_labels(phrygian_spec, spelling_mode: :practical)

    assert locrian_labels.parent_scale == "Db Major"
    assert phrygian_labels.parent_scale == "Ab Major"
  end
end
