defmodule PhoenixTtsWeb.HistoryAudioController do
  use PhoenixTtsWeb, :controller

  alias PhoenixTts.Audio

  def show(conn, %{"history_item_id" => history_item_id} = params) do
    disposition =
      case Map.get(params, "download") do
        "1" -> "attachment"
        _ -> "inline"
      end

    case Audio.fetch_history_audio(history_item_id) do
      {:ok, %{audio: audio, content_type: content_type}} ->
        filename = "history-#{history_item_id}.mp3"

        conn
        |> put_resp_content_type(content_type || "audio/mpeg")
        |> put_resp_header("content-disposition", "#{disposition}; filename=\"#{filename}\"")
        |> send_resp(200, audio)

      {:error, reason} ->
        conn
        |> put_flash(:error, normalize_error(reason))
        |> redirect(to: ~p"/")
    end
  end

  defp normalize_error(message) when is_binary(message), do: message
  defp normalize_error(other), do: "Falha ao carregar audio do histórico: #{inspect(other)}"
end
