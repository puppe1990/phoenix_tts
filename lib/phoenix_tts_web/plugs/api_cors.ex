defmodule PhoenixTtsWeb.Plugs.ApiCors do
  @moduledoc false

  import Plug.Conn

  @default_headers "authorization,content-type"
  @default_methods "GET,POST,OPTIONS"

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = List.first(get_req_header(conn, "origin"))
    allowed_origins = Application.get_env(:phoenix_tts, :api_allowed_origins, [])

    conn =
      conn
      |> maybe_put_allow_origin(origin, allowed_origins)
      |> put_resp_header("vary", "origin")
      |> put_resp_header("access-control-allow-methods", @default_methods)
      |> put_resp_header("access-control-allow-headers", @default_headers)
      |> put_resp_header("access-control-max-age", "86400")

    if conn.method == "OPTIONS" do
      conn
      |> send_resp(:no_content, "")
      |> halt()
    else
      conn
    end
  end

  defp maybe_put_allow_origin(conn, nil, _allowed_origins), do: conn

  defp maybe_put_allow_origin(conn, _origin, ["*"]) do
    put_resp_header(conn, "access-control-allow-origin", "*")
  end

  defp maybe_put_allow_origin(conn, origin, allowed_origins) do
    if origin in allowed_origins do
      put_resp_header(conn, "access-control-allow-origin", origin)
    else
      conn
    end
  end
end
