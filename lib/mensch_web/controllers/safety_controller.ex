defmodule MenschWeb.SafetyController do
  use MenschWeb, :controller

  alias Mensch.Player

  def panic_stop(conn, _params) do
    Player.stop()
    Player.panic()

    conn
    |> put_flash(:info, "Panic stop sent")
    |> redirect(to: redirect_path(conn))
  end

  defp redirect_path(conn) do
    referer = conn |> get_req_header("referer") |> List.first()

    case URI.parse(referer || "") do
      %URI{path: path, query: query} when is_binary(path) ->
        if String.starts_with?(path, "/") do
          if is_binary(query) and query != "" do
            path <> "?" <> query
          else
            path
          end
        else
          "/"
        end

      _ ->
        "/"
    end
  end
end
