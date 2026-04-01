defmodule PhoenixTtsWeb.ApiFallbackController do
  use PhoenixTtsWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: translate_errors(changeset)})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  def call(conn, {:error, {:internal_server_error, message}}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: message})
  end

  def call(conn, {:error, message}) when is_binary(message) do
    conn
    |> put_status(:bad_gateway)
    |> json(%{error: message})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:bad_gateway)
    |> json(%{error: inspect(reason)})
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
