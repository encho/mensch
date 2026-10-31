defmodule MenschWeb.ChordProgressionShowLiveTest do
  use MenschWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mensch.ChordProgressions
  alias Mensch.Harmony.ChordSpec

  setup do
    original_dir = Application.get_env(:mensch, :chord_progressions_dir)

    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "mensch_chord_progression_show_test_#{System.unique_integer([:positive])}"
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

  test "saves selected chords as a reordered new progression", %{conn: conn} do
    assert {:ok, source} =
             ChordProgressions.create_progression(
               "Source",
               "",
               [chord(:c), chord(:d), chord(:e)]
             )

    {:ok, view, _html} = live(conn, ~p"/chord-progressions/#{source.id}")

    view
    |> element("#selected-chord-form-0")
    |> render_change(%{"selected_index" => "0", "selected" => "true"})

    view
    |> element("#selected-chord-form-2")
    |> render_change(%{"selected_index" => "2", "selected" => "true"})

    view
    |> element("button[phx-click='open_save_selected_modal']")
    |> render_click()

    assert has_element?(view, "#save-selected-chords-form")

    view
    |> element(
      "button[phx-click='move_selected_chord'][phx-value-index='2'][phx-value-direction='up']"
    )
    |> render_click()

    view
    |> element("#save-selected-chords-form")
    |> render_submit(%{
      "selection" => %{
        "name" => "Selected subset",
        "description" => "picked chords"
      }
    })

    assert_redirect(view, ~p"/chord-progressions/selected_subset")

    assert {:ok, saved} = ChordProgressions.fetch_progression("selected_subset")
    roots = Enum.map(saved.progression.chords, &ChordSpec.root/1)

    assert roots == [:e, :c]
  end

  defp chord(root) do
    ChordSpec.new!(%{
      harmonic_identity: %ChordSpec.HarmonicIdentity{root: root, quality: :maj},
      octave: 3,
      inversion: 0
    })
  end
end
