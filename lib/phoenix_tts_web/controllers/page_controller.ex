defmodule PhoenixTtsWeb.PageController do
  use PhoenixTtsWeb, :controller

  @api_markdown_path Path.expand("../../../docs/API.md", __DIR__)
  @openapi_path Path.expand("../../../docs/openapi.yaml", __DIR__)
  @external_resource @api_markdown_path
  @external_resource @openapi_path
  @api_markdown File.read!(@api_markdown_path)
  @openapi_yaml File.read!(@openapi_path)

  def home(conn, _params) do
    render(conn, :home)
  end

  def api_docs(conn, _params) do
    render(conn, :api_docs, openapi_url: ~p"/openapi.yaml", api_base_url: ~p"/api")
  end

  def api_markdown(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, @api_markdown)
  end

  def openapi(conn, _params) do
    conn
    |> put_resp_content_type("application/yaml")
    |> send_resp(200, @openapi_yaml)
  end
end
