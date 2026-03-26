defmodule PhoenixTtsWeb.PageController do
  use PhoenixTtsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
