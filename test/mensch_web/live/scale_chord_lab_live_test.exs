defmodule MenschWeb.ScaleChordLabLiveTest do
  use MenschWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders default scale chord lab view", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/scale-chord-lab")

    assert html =~ "Scale Chord Lab"
    assert html =~ "1) Define Scale"
    assert html =~ "2) Chord Strategy"
    assert html =~ "3) Select Degree"
    assert html =~ "4) Generated Chord"
    assert html =~ "5) Resolved Harmonic Identities"
    assert html =~ "Quality"
    assert html =~ "Chord:"
  end

  test "changing degree updates chord notes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/scale-chord-lab")

    assert has_element?(view, "#scale-chord-lab-full-keyboard")
    assert has_element?(view, "#scale-chord-lab-degree-buttons")

    view
    |> element("button[phx-click='set_degree'][phx-value-degree='2']")
    |> render_click()

    html = render(view)

    assert html =~ "Chord: D"
    assert html =~ "F"
    assert html =~ "A"
    assert has_element?(view, "#scale-chord-lab-resolved-identities")
  end

  test "switching to standalone scale hides mode selector and still generates chord", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/scale-chord-lab")

    view
    |> element("form[phx-change='set_family']")
    |> render_change(%{"family" => "whole_tone"})

    html = render(view)

    assert html =~ "No mode (standalone scale)"
    assert html =~ "Chord:"
    assert has_element?(view, "#scale-chord-lab-full-keyboard")
  end

  test "switching shape updates chord output", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/scale-chord-lab")

    view
    |> element("form[phx-change='set_shape']")
    |> render_change(%{"shape" => "seventh"})

    html = render(view)

    assert html =~ "Shape: Seventh"
    assert html =~ "Chord: C"
    assert html =~ "B"
  end

  test "switching to add6 shape updates chord", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/scale-chord-lab")

    view
    |> element("form[phx-change='set_shape']")
    |> render_change(%{"shape" => "add6"})

    html = render(view)

    assert html =~ "Shape: Add 6"
    assert html =~ "Chord: C"
    assert html =~ "A"
  end

  test "switching to quartal updates output", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/scale-chord-lab")

    view
    |> element("form[phx-change='set_strategy']")
    |> render_change(%{"strategy" => "quartal"})

    html = render(view)

    assert html =~ "Chord: C"
    assert html =~ "F"
    assert html =~ "B"
  end

  test "switching to quintal updates output", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/scale-chord-lab")

    view
    |> element("form[phx-change='set_strategy']")
    |> render_change(%{"strategy" => "quintal"})

    html = render(view)

    assert html =~ "Chord: C"
    assert html =~ "G"
    assert html =~ "D"
  end

  test "c dorian degree 1 seventh resolves cm7 first", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/scale-chord-lab")

    view
    |> element("form[phx-change='set_mode']")
    |> render_change(%{"mode" => "2"})

    view
    |> element("form[phx-change='set_shape']")
    |> render_change(%{"shape" => "seventh"})

    html = render(view)

    assert has_element?(view, "#scale-chord-lab-resolved-identities")
    assert html =~ "1. Cm7"
  end
end
