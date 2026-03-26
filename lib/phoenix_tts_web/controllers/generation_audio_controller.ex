defmodule PhoenixTtsWeb.GenerationAudioController do
  use PhoenixTtsWeb, :controller

  alias PhoenixTts.Audio

  def show(conn, %{"id" => id} = params) do
    disposition =
      case Map.get(params, "download") do
        "1" -> "attachment"
        _ -> "inline"
      end

    case Audio.get_generation(id) do
      %{audio_path: audio_path, content_type: content_type} = generation ->
        absolute_path = Path.join(Audio.storage_dir(), audio_path)

        case File.read(absolute_path) do
          {:ok, audio} ->
            filename = "generation-#{generation.id}.mp3"

            conn
            |> put_resp_content_type(content_type || "audio/mpeg")
            |> put_resp_header("content-disposition", "#{disposition}; filename=\"#{filename}\"")
            |> send_resp(200, audio)

          {:error, reason} ->
            redirect_with_error(conn, "Falha ao carregar áudio local: #{inspect(reason)}")
        end

      nil ->
        redirect_with_error(conn, "Áudio local não encontrado.")
    end
  end

  defp redirect_with_error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/recentes")
  end
end
