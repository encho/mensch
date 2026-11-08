defmodule MenschWeb.SafetyControllerTest do
  use MenschWeb.ConnCase, async: true

  test "POST /panic-stop redirects and sets flash", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "/chord-matrix")
      |> post(~p"/panic-stop")

    assert redirected_to(conn) == "/chord-matrix"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Panic stop sent"
  end
end
