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
    assert ChordSpec.root(assignment.chord_spec) == :g

    view
    |> element("button[phx-click='clear_selected_pad_assignment']")
    |> render_click()

    assert render(view) =~ "Pad cleared"

    assert {:ok, persisted_after_clear} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert Map.get(persisted_after_clear.chord_matrix.assignments, {0, 0}) == nil
  end

  test "shows default bpm and allows updating it", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    assert render(view) =~ "120 BPM"

    view
    |> form("#matrix-bpm-form", %{"chord_matrix" => %{"bpm" => "138"}})
    |> render_submit()

    assert render(view) =~ "BPM updated"
    assert render(view) =~ "138 BPM"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.bpm == 138
  end

  test "rejects invalid bpm updates", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> form("#matrix-bpm-form", %{"chord_matrix" => %{"bpm" => "0"}})
    |> render_submit()

    assert render(view) =~ "BPM must be a positive integer"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.bpm == 120
  end

  test "shows default duration and allows updating it", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    assert render(view) =~ "4000 mbeats"

    view
    |> form("#matrix-duration-form", %{"chord_matrix" => %{"duration_mbeats" => "6000"}})
    |> render_submit()

    assert render(view) =~ "Duration updated"
    assert render(view) =~ "6000 mbeats"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.duration_mbeats == 6000
  end

  test "shows default frame mbeats and allows updating it", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    assert render(view) =~ "Frame 50 mbeats"

    view
    |> form("#matrix-frame-mbeats-form", %{"chord_matrix" => %{"frame_mbeats" => "25"}})
    |> render_submit()

    assert render(view) =~ "Frame mbeats updated"
    assert render(view) =~ "Frame 25 mbeats"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.frame_mbeats == 25
  end

  test "rejects invalid frame mbeats updates", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> form("#matrix-frame-mbeats-form", %{"chord_matrix" => %{"frame_mbeats" => "30"}})
    |> render_submit()

    assert render(view) =~ "Frame mbeats must be a positive divisor of 1000"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.frame_mbeats == 50
  end

  test "rejects invalid duration updates", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> form("#matrix-duration-form", %{"chord_matrix" => %{"duration_mbeats" => "0"}})
    |> render_submit()

    assert render(view) =~ "Duration must be a positive integer"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.duration_mbeats == 4000
  end

  test "shows default time signature and allows updating it", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    assert render(view) =~ "TS 4/4"

    view
    |> form("#matrix-time-signature-form", %{
      "chord_matrix" => %{"time_signature_numerator" => "7", "time_signature_denominator" => "8"}
    })
    |> render_submit()

    assert render(view) =~ "Time signature updated"
    assert render(view) =~ "TS 7/8"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.time_signature == {7, 8}
  end

  test "rejects invalid time signature updates", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> form("#matrix-time-signature-form", %{
      "chord_matrix" => %{"time_signature_numerator" => "0", "time_signature_denominator" => "4"}
    })
    |> render_submit()

    assert render(view) =~ "Time signature must be positive integers"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.time_signature == {4, 4}
  end

  test "shows machine form and persists machine settings", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    assert has_element?(view, "#matrix-machine-form")

    view
    |> form("#matrix-machine-form", %{
      "machine" => %{"blueprint_id" => "progression__steady_strum__strum1"}
    })
    |> render_change()

    view
    |> form("#matrix-machine-form", %{
      "machine" => %{
        "blueprint_id" => "progression__steady_strum__strum1",
        "additional" => %{
          "velocity" => "88",
          "pressure_attack_mbeats" => "210.0",
          "pressure_curve" => "square"
        }
      }
    })
    |> render_submit()

    assert render(view) =~ "Machine settings updated"

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert persisted.chord_matrix.machine.blueprint_id == "progression__steady_strum__strum1"
    assert persisted.chord_matrix.machine.additional_params["velocity"] == 88
    assert persisted.chord_matrix.machine.additional_params["pressure_attack_mbeats"] == 210.0
    assert persisted.chord_matrix.machine.additional_params["pressure_curve"] == "square"
  end

  test "toggles global matrix play mode", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(1, 1)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    assert has_element?(view, "#toggle-matrix-play-mode[aria-checked='true']")

    view
    |> element("#toggle-matrix-play-mode")
    |> render_click()

    assert has_element?(view, "#toggle-matrix-play-mode[aria-checked='false']")
  end

  test "shows detail mpe charts only when enabled and a pad is pressed", %{conn: conn} do
    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(1, 1)

    assert {:ok, _updated_record} =
             ChordMatrices.assign_chord_to_pad(
               matrix_record.id,
               0,
               0,
               chord(:c, :maj7),
               %{
                 source_progression_id: "test",
                 source_progression_name: "Test",
                 source_chord_index: 0
               }
             )

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    assert has_element?(view, "#pad-mpe-detail-panel")
    assert render(view) =~ "MPE charts are hidden"

    view
    |> element("#toggle-display-detail-mpe-data")
    |> render_click()

    assert has_element?(view, "#pad-mpe-detail-panel")
    assert render(view) =~ "Detail MPE Data"

    view
    |> element("#pad-0-0")
    |> render_click()

    assert render(view) =~ "Note matrix"
    assert render(view) =~ "Pressure"
    assert render(view) =~ "Slide (Aftertouch)"
    assert render(view) =~ "Bend (Vibrato)"

    rendered = render(view)
    assert rendered =~ ~r/Note matrix.*Pressure/s
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

  test "assigns full progression across selected row and clears remaining pads", %{conn: conn} do
    assert {:ok, progression_record} =
             ChordProgressions.create_progression(
               "Row Fill",
               "",
               [chord(:c, :maj7), chord(:g, :min7)]
             )

    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(2, 4)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> element("#row-header-0")
    |> render_click()

    view
    |> element("#toggle-progression-#{progression_record.id}")
    |> render_click()

    view
    |> element("#assign-sequence-#{progression_record.id}")
    |> render_click()

    assert render(view) =~ "Assigned 2 chord(s) to selected row 1."

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)

    row_assignments = persisted.chord_matrix.assignments

    assert ChordSpec.root(row_assignments[{0, 0}].chord_spec) == :c
    assert ChordSpec.root(row_assignments[{0, 1}].chord_spec) == :g
    assert Map.get(row_assignments, {0, 2}) == nil
    assert Map.get(row_assignments, {0, 3}) == nil
  end

  test "assigns full progression across selected column from top to bottom", %{conn: conn} do
    assert {:ok, progression_record} =
             ChordProgressions.create_progression(
               "Column Fill",
               "",
               [chord(:d, :min7), chord(:f, :maj7)]
             )

    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(4, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> element("#column-header-1")
    |> render_click()

    view
    |> element("#toggle-progression-#{progression_record.id}")
    |> render_click()

    view
    |> element("#assign-sequence-#{progression_record.id}")
    |> render_click()

    assert render(view) =~ "Assigned 2 chord(s) to selected column 2."

    assert {:ok, persisted} = ChordMatrices.fetch_chord_matrix(matrix_record.id)

    column_assignments = persisted.chord_matrix.assignments

    assert ChordSpec.root(column_assignments[{0, 1}].chord_spec) == :d
    assert ChordSpec.root(column_assignments[{1, 1}].chord_spec) == :f
    assert Map.get(column_assignments, {2, 1}) == nil
    assert Map.get(column_assignments, {3, 1}) == nil
  end

  test "shows truncation modal and assigns only available pads after confirmation", %{conn: conn} do
    assert {:ok, progression_record} =
             ChordProgressions.create_progression(
               "Too Long",
               "",
               [chord(:c, :maj7), chord(:d, :min7), chord(:e, :min7)]
             )

    assert {:ok, matrix_record} = ChordMatrices.create_chord_matrix(1, 2)

    {:ok, view, _html} = live(conn, ~p"/chord-matrix/#{matrix_record.id}")

    view
    |> element("#row-header-0")
    |> render_click()

    view
    |> element("#toggle-progression-#{progression_record.id}")
    |> render_click()

    view
    |> element("#assign-sequence-#{progression_record.id}")
    |> render_click()

    assert has_element?(view, "#bulk-assign-modal")

    assert {:ok, before_confirm} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert before_confirm.chord_matrix.assignments == %{}

    view
    |> element("#bulk-assign-confirm")
    |> render_click()

    assert render(view) =~ "Assigned 2 chord(s) to selected row 1. Skipped 1 trailing chord(s)."

    assert {:ok, after_confirm} = ChordMatrices.fetch_chord_matrix(matrix_record.id)
    assert ChordSpec.root(after_confirm.chord_matrix.assignments[{0, 0}].chord_spec) == :c
    assert ChordSpec.root(after_confirm.chord_matrix.assignments[{0, 1}].chord_spec) == :d
  end

  defp chord(root, quality) do
    ChordSpec.new!(%{
      harmonic_identity: %ChordSpec.HarmonicIdentity{root: root, quality: quality},
      octave: 3,
      inversion: 0
    })
  end
end
