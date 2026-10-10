defmodule Mensch.ChordListsTest do
  use ExUnit.Case, async: false

  alias Mensch.ChordLists
  alias Mensch.Harmony.ChordSpec.Parameters

  setup do
    previous = Application.get_env(:mensch, :chord_lists_dir)

    temp_dir =
      Path.join(System.tmp_dir!(), "mensch_chord_lists_#{System.unique_integer([:positive])}")

    Application.put_env(:mensch, :chord_lists_dir, temp_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:mensch, :chord_lists_dir, previous)
      else
        Application.delete_env(:mensch, :chord_lists_dir)
      end

      File.rm_rf(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  test "creates list, adds entry, and deletes entry", %{temp_dir: temp_dir} do
    assert {:ok, list} = ChordLists.create_list("My First List")
    assert list.name == "My First List"

    assert [%{name: "My First List"}] = ChordLists.list_lists()

    values = %{
      "root" => "c",
      "quality" => "maj7",
      "octave" => "3",
      "inversion" => "0",
      "_unused_voicing_type" => ""
    }

    result = %{final_notes: [48, 52, 55, 59]}

    assert {:ok, updated} = ChordLists.add_entry(list.id, values, result)
    assert length(updated.entries) == 1

    persisted_parameters = updated.entries |> List.first() |> Map.fetch!(:parameters)
    assert match?(%Parameters{}, persisted_parameters)
    assert persisted_parameters.octave == 3
    assert persisted_parameters.inversion == 0
    assert persisted_parameters.voice_count == nil

    entry_id = updated.entries |> List.first() |> Map.fetch!(:id)

    assert {:ok, reloaded} = ChordLists.fetch_list(list.id)
    assert length(reloaded.entries) == 1

    reloaded_parameters = reloaded.entries |> List.first() |> Map.fetch!(:parameters)
    assert match?(%Parameters{}, reloaded_parameters)

    path = Path.join(temp_dir, list.id <> ".exs")
    content = File.read!(path)
    refute String.contains?(content, "~c\"")

    assert {:ok, after_delete} = ChordLists.delete_entry(list.id, entry_id)
    assert after_delete.entries == []
  end
end
