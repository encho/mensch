defmodule MenschWeb.HomeRedirectController do
  use MenschWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/samples")
  end
end
