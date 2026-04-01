defmodule PhoenixTtsWeb.Plugs.ApiAuth do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts), do: conn

  def call(conn, _opts) do
    case Application.get_env(:phoenix_tts, :api_auth_token) do
      token when is_binary(token) and token != "" ->
        authorize(conn, token)

      _ ->
        conn
    end
  end

  defp authorize(conn, expected_token) do
    provided_token =
      conn
      |> get_req_header("authorization")
      |> List.first()
      |> extract_bearer_token()

    if provided_token == expected_token do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized"})
      |> halt()
    end
  end

  defp extract_bearer_token("Bearer " <> token), do: token
  defp extract_bearer_token("bearer " <> token), do: token
  defp extract_bearer_token(_value), do: nil
end
