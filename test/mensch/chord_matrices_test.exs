defmodule Mensch.ChordMatricesTest do
  use ExUnit.Case, async: false

  alias Mensch.ChordMatrices
  alias Mensch.Harmony.ChordSpec

  setup do
    original_dir = Application.get_env(:mensch, :chord_matrices_dir)

    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "mensch_chord_matrices_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:mensch, :chord_matrices_dir, temp_dir)
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      if original_dir do
        Application.put_env(:mensch, :chord_matrices_dir, original_dir)
      else
        Application.delete_env(:mensch, :chord_matrices_dir)
      end

      File.rm_rf(temp_dir)
    end)

    :ok
  end

  test "assign_chord_to_pad persists assignment metadata and chord snapshot" do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    assert {:ok, updated_record} =
             ChordMatrices.assign_chord_to_pad(
               matrix_record.id,
               0,
               1,
               chord(:c, :maj7),
               %{
                 source_progression_id: "ii_v_i",
                 source_progression_name: "II V I",
                 source_chord_index: 2
               }
             )

    assignment = updated_record.chord_matrix.assignments[{0, 1}]

    assert %ChordSpec{} = assignment.chord_spec
    assert ChordSpec.root(assignment.chord_spec) == :c
    assert assignment.source_progression_id == "ii_v_i"
    assert assignment.source_progression_name == "II V I"
    assert assignment.source_chord_index == 2

    assert {:ok, reloaded_record} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    reloaded_assignment = reloaded_record.chord_matrix.assignments[{0, 1}]

    assert ChordSpec.root(reloaded_assignment.chord_spec) == :c
    assert reloaded_assignment.source_progression_id == "ii_v_i"
  end

  test "clear_pad_assignment removes assignment from matrix" do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    assert {:ok, assigned_record} =
             ChordMatrices.assign_chord_to_pad(
               matrix_record.id,
               1,
               1,
               chord(:g, :min7),
               %{
                 source_progression_id: "minor_turn",
                 source_progression_name: "Minor Turn",
                 source_chord_index: 1
               }
             )

    assert assigned_record.chord_matrix.assignments[{1, 1}] != nil

    assert {:ok, cleared_record} = ChordMatrices.clear_pad_assignment(matrix_record.id, 1, 1)
    assert Map.get(cleared_record.chord_matrix.assignments, {1, 1}) == nil
  end

  test "fetch_chord_matrix normalizes v1 files without assignments" do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    legacy_record =
      %{
        version: 1,
        id: "legacy",
        inserted_at: now,
        updated_at: now,
        chord_matrix: %{number_rows: 3, number_columns: 4}
      }
      |> inspect(pretty: true, width: 100)

    path = Path.join(Application.fetch_env!(:mensch, :chord_matrices_dir), "legacy.exs")
    assert :ok = File.write(path, legacy_record <> "\n")

    assert {:ok, loaded} = ChordMatrices.fetch_chord_matrix("legacy")
    assert loaded.chord_matrix.number_rows == 3
    assert loaded.chord_matrix.number_columns == 4
    assert loaded.chord_matrix.assignments == %{}
  end

  test "insert and remove row shifts assignments as expected" do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    assert {:ok, _record} =
             ChordMatrices.assign_chord_to_pad(
               matrix_record.id,
               1,
               0,
               chord(:f, :maj7),
               %{
                 source_progression_id: "row_shift",
                 source_progression_name: "Row Shift",
                 source_chord_index: 0
               }
             )

    assert {:ok, inserted_record} = ChordMatrices.insert_row_before(matrix_record.id, 1)
    assert inserted_record.chord_matrix.number_rows == 3
    assert Map.has_key?(inserted_record.chord_matrix.assignments, {2, 0})

    assert {:ok, removed_record} = ChordMatrices.remove_row(matrix_record.id, 1)
    assert removed_record.chord_matrix.number_rows == 2
    assert Map.has_key?(removed_record.chord_matrix.assignments, {1, 0})
  end

  test "insert and remove column shifts assignments as expected" do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    assert {:ok, _record} =
             ChordMatrices.assign_chord_to_pad(
               matrix_record.id,
               0,
               1,
               chord(:d, :min7),
               %{
                 source_progression_id: "column_shift",
                 source_progression_name: "Column Shift",
                 source_chord_index: 0
               }
             )

    assert {:ok, inserted_record} = ChordMatrices.insert_column_left(matrix_record.id, 1)
    assert inserted_record.chord_matrix.number_columns == 3
    assert Map.has_key?(inserted_record.chord_matrix.assignments, {0, 2})

    assert {:ok, removed_record} = ChordMatrices.remove_column(matrix_record.id, 1)
    assert removed_record.chord_matrix.number_columns == 2
    assert Map.has_key?(removed_record.chord_matrix.assignments, {0, 1})
  end

  defp chord(root, quality) do
    ChordSpec.new!(%{
      harmonic_identity: %ChordSpec.HarmonicIdentity{root: root, quality: quality},
      octave: 3,
      inversion: 0
    })
  end
end
