defmodule MenschWeb.ChordMatrixShowLiveTest do
  use MenschWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mensch.ChordMatrices
  alias Mensch.ChordProgressions
  alias Mensch.Harmony.ChordSpec

  setup do
    original_matrices_dir = Application.get_env(:mensch, :chord_matrices_dir)
    original_progressions_dir = Application.get_env(:mensch, :chord_progressions_dir)

    matrices_dir =
      Path.join(
        System.tmp_dir!(),
        "mensch_chord_matrix_show_matrices_#{System.unique_integer([:positive])}"
      )

    progressions_dir =
      Path.join(
        System.tmp_dir!(),
        "mensch_chord_matrix_show_progressions_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:mensch, :chord_matrices_dir, matrices_dir)
    Application.put_env(:mensch, :chord_progressions_dir, progressions_dir)

    File.mkdir_p!(matrices_dir)
    File.mkdir_p!(progressions_dir)

    on_exit(fn ->
      if original_matrices_dir do
        Application.put_env(:mensch, :chord_matrices_dir, original_matrices_dir)
      else
        Application.delete_env(:mensch, :chord_matrices_dir)
      end

      if original_progressions_dir do
        Application.put_env(:mensch, :chord_progressions_dir, original_progressions_dir)
      else
        Application.delete_env(:mensch, :chord_progressions_dir)
      end

      File.rm_rf(matrices_dir)
      File.rm_rf(progressions_dir)
    end)

    :ok
  end

  test "assigns and clears a pad chord from progression side panel", %{conn: conn} do
    assert {:ok, progression_record} =
             ChordProgressions.create_progression(
               "Source Progression",
               "",
               [chord(:c, :maj7), chord(:g, :min7)]
             )

    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> element("#pad-0-0")
    |> render_click()

    view
    |> element("#toggle-progression-#{progression_record.id}")
    |> render_click()

    assert has_element?(view, "#assign-#{progression_record.id}-1")

    view
    |> element("#assign-#{progression_record.id}-1")
    |> render_click()

    assert render(view) =~ "Assigned chord to pad"
    assert has_element?(view, "#chord-matrix-active-keyboard")
    assert render(view) =~ "Selected pad"

    assert {:ok, persisted_after_assign} = ChordMatrices.fetch_chord_matrix(matrix_record.id)

    assignment = persisted_after_assign.chord_matrix.assignments[{0, 0}]
    assert assignment != nil
    assert assignment.source_progression_id == progression_record.id
    assert assignment.source_chord_index == 1
    assert ChordSpec.root(assignment.chord_spec) == :g

    view
    |> element("button[phx-click='clear_selected_pad_assignment']")
    |> render_click()

    assert render(view) =~ "Pad cleared"

    assert {:ok, persisted_after_clear} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert Map.get(persisted_after_clear.chord_matrix.assignments, {0, 0}) == nil
  end

  test "toggles global matrix play mode", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(1, 1)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    assert has_element?(view, "#toggle-matrix-play-mode[aria-checked='false']")

    view
    |> element("#toggle-matrix-play-mode")
    |> render_click()

    assert has_element?(view, "#toggle-matrix-play-mode[aria-checked='true']")
  end

  test "inserts and removes selected row and column", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> element("#row-header-0")
    |> render_click()

    view
    |> element("#row-insert-after")
    |> render_click()

    assert render(view) =~ "3 rows x 2 columns"

    view
    |> element("#column-header-0")
    |> render_click()

    view
    |> element("#column-insert-right")
    |> render_click()

    assert render(view) =~ "3 rows x 3 columns"

    view
    |> element("#row-header-0")
    |> render_click()

    view
    |> element("#row-remove")
    |> render_click()

    assert render(view) =~ "2 rows x 3 columns"

    view
    |> element("#column-header-0")
    |> render_click()

    view
    |> element("#column-remove")
    |> render_click()

    assert render(view) =~ "2 rows x 2 columns"
  end

  test "moves selected row and column", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(3, 3)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> element("#row-header-1")
    |> render_click()

    view
    |> element("#row-move-up")
    |> render_click()

    assert render(view) =~ "Moved selected row up"

    view
    |> element("#column-header-1")
    |> render_click()

    view
    |> element("#column-move-right")
    |> render_click()

    assert render(view) =~ "Moved selected column right"
  end

  defp chord(root, quality) do
    ChordSpec.new!(%{
      harmonic_identity: %ChordSpec.HarmonicIdentity{root: root, quality: quality},
      octave: 3,
      inversion: 0
    })
  end
end
