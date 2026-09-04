defmodule MenschWeb.PageController do
  use MenschWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
