defmodule Mensch.ChordProgressionsTest do
  use ExUnit.Case, async: false

  alias Mensch.ChordProgressions
  alias Mensch.Harmony.ChordSpec

  setup do
    original_dir = Application.get_env(:mensch, :chord_progressions_dir)

    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "mensch_chord_progressions_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:mensch, :chord_progressions_dir, temp_dir)
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      if original_dir do
        Application.put_env(:mensch, :chord_progressions_dir, original_dir)
      else
        Application.delete_env(:mensch, :chord_progressions_dir)
      end

      File.rm_rf(temp_dir)
    end)

    :ok
  end

  test "merge_progressions creates a new progression in selected order" do
    assert {:ok, first} =
             ChordProgressions.create_progression("First", "", [chord(:c), chord(:g)])

    assert {:ok, second} =
             ChordProgressions.create_progression("Second", "", [chord(:d)])

    assert {:ok, merged} =
             ChordProgressions.merge_progressions(
               "Merged",
               "combined",
               [second.id, first.id]
             )

    assert {:ok, merged_record} = ChordProgressions.fetch_progression(merged.id)
    roots = Enum.map(merged_record.progression.chords, &ChordSpec.root/1)

    assert roots == [:d, :c, :g]
    assert {:ok, _still_there} = ChordProgressions.fetch_progression(first.id)
    assert {:ok, _still_there} = ChordProgressions.fetch_progression(second.id)
  end

  test "merge_progressions requires at least one selected source" do
    assert {:error, :no_sources_selected} =
             ChordProgressions.merge_progressions("Merged", "", [])
  end

  test "merge_progressions returns missing source information" do
    assert {:error, {:source_load_failed, "missing", :not_found}} =
             ChordProgressions.merge_progressions("Merged", "", ["missing"])
  end

  defp chord(root) do
    ChordSpec.new!(%{
      harmonic_identity: %ChordSpec.HarmonicIdentity{root: root, quality: :maj},
      octave: 3,
      inversion: 0
    })
  end
end
