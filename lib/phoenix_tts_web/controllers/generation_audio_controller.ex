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
      %{audio_binary: audio, content_type: content_type} = generation when is_binary(audio) ->
        send_audio(conn, generation.id, disposition, content_type, audio)

      %{audio_path: audio_path, content_type: content_type} = generation
      when is_binary(audio_path) and audio_path != "" ->
        absolute_path =
          if Path.type(audio_path) == :absolute do
            audio_path
          else
            Path.join(Audio.storage_dir(), audio_path)
          end

        case File.read(absolute_path) do
          {:ok, audio} ->
            send_audio(conn, generation.id, disposition, content_type, audio)

          {:error, reason} ->
            redirect_with_error(conn, "Falha ao carregar áudio legado: #{inspect(reason)}")
        end

      nil ->
        redirect_with_error(conn, "Áudio não encontrado.")

      _generation ->
        redirect_with_error(conn, "Áudio não encontrado.")
    end
  end

  defp send_audio(conn, generation_id, disposition, content_type, audio) do
    filename = "generation-#{generation_id}.mp3"

    conn
    |> put_resp_content_type(content_type || "audio/mpeg")
    |> put_resp_header("content-disposition", "#{disposition}; filename=\"#{filename}\"")
    |> send_resp(200, audio)
  end

  defp redirect_with_error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/recentes")
  end
end
