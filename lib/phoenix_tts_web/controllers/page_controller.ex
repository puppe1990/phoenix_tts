defmodule PhoenixTtsWeb.PageController do
  use PhoenixTtsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def api_docs(conn, _params) do
    render(conn, :api_docs, openapi_url: ~p"/openapi.yaml", api_base_url: ~p"/api")
  end

  def api_markdown(conn, _params) do
    markdown_path = Path.expand("../../../docs/API.md", __DIR__)

    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, File.read!(markdown_path))
  end

  def openapi(conn, _params) do
    openapi_path = Path.expand("../../../docs/openapi.yaml", __DIR__)

    conn
    |> put_resp_content_type("application/yaml")
    |> send_resp(200, File.read!(openapi_path))
  end
end
