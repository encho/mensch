defmodule MenschWeb.ProgressionLiveTest do
  use MenschWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mensch.ChordProgressions
  alias Mensch.Harmony.ChordSpec

  setup do
    original_dir = Application.get_env(:mensch, :chord_progressions_dir)

    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "mensch_progression_live_test_#{System.unique_integer([:positive])}"
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

  test "uses blueprint chords as source and derives save metadata", %{conn: conn} do
    assert {:ok, source} =
             ChordProgressions.create_progression(
               "Blueprint Name",
               "Blueprint Description",
               [chord(:c), chord(:g)]
             )

    {:ok, view, _html} = live(conn, ~p"/chord-progressions/new?blueprint_id=#{source.id}")

    view
    |> element("#save-stage-0")
    |> render_click()

    assert has_element?(
             view,
             "input[name='progression[name]'][value='Blueprint Name (variation)']"
           )

    assert render(view) =~ "Variation of Blueprint Name. Blueprint Description"

    view
    |> element("form[phx-submit='save_progression']")
    |> render_submit(%{
      "progression" => %{
        "name" => "Blueprint Name (variation)",
        "description" => "Variation of Blueprint Name. Blueprint Description"
      }
    })

    assert render(view) =~ "Progression saved"

    assert {:ok, saved} = ChordProgressions.fetch_progression("blueprint_name_variation")

    roots = Enum.map(saved.progression.chords, &ChordSpec.root/1)
    assert roots == [:c, :g]
  end

  defp chord(root) do
    ChordSpec.new!(%{
      harmonic_identity: %ChordSpec.HarmonicIdentity{root: root, quality: :maj},
      octave: 3,
      inversion: 0
    })
  end
end
