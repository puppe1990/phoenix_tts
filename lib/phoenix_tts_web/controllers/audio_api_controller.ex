defmodule PhoenixTtsWeb.AudioApiController do
  use PhoenixTtsWeb, :controller

  alias PhoenixTts.Audio
  alias PhoenixTts.Audio.Generation

  action_fallback PhoenixTtsWeb.ApiFallbackController

  def options(conn, _params) do
    send_resp(conn, :no_content, "")
  end

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Audio.list_generations(), &serialize_generation/1)})
  end

  def show(conn, %{"id" => id}) do
    case Audio.get_generation(id) do
      %Generation{} = generation ->
        json(conn, %{data: serialize_generation(generation)})

      nil ->
        {:error, :not_found}
    end
  end

  def create(conn, params) do
    with {:ok, %Generation{} = generation} <- Audio.create_generation(params) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize_generation(generation)})
    end
  end

  def voices(conn, _params) do
    json(conn, %{data: Audio.available_voices()})
  end

  def models(conn, _params) do
    json(conn, %{data: Audio.available_models()})
  end

  def subscription(conn, _params) do
    with {:ok, overview} <- Audio.subscription_overview() do
      json(conn, %{data: overview})
    end
  end

  def history(conn, params) do
    request_params =
      params
      |> Map.take(["page_size", "start_after_history_item_id"])
      |> normalize_page_size()

    with {:ok, history_page} <- Audio.remote_history_page(request_params) do
      json(conn, %{data: history_page})
    end
  end

  def generation_audio(conn, %{"id" => id} = params) do
    disposition = audio_disposition(params)

    case Audio.get_generation(id) do
      %Generation{audio_binary: audio} = generation when is_binary(audio) ->
        send_audio(conn, generation.id, disposition, generation.content_type, audio, "generation")

      %Generation{audio_path: audio_path} = generation
      when is_binary(audio_path) and audio_path != "" ->
        case load_legacy_audio(audio_path) do
          {:ok, audio} ->
            send_audio(
              conn,
              generation.id,
              disposition,
              generation.content_type,
              audio,
              "generation"
            )

          {:error, reason} ->
            {:error,
             {:internal_server_error, "Falha ao carregar áudio legado: #{inspect(reason)}"}}
        end

      nil ->
        {:error, :not_found}

      _generation ->
        {:error, :not_found}
    end
  end

  def history_audio(conn, %{"history_item_id" => history_item_id} = params) do
    disposition = audio_disposition(params)

    with {:ok, %{audio: audio, content_type: content_type}} <-
           Audio.fetch_history_audio(history_item_id) do
      send_audio(conn, history_item_id, disposition, content_type, audio, "history")
    end
  end

  defp normalize_page_size(%{"page_size" => page_size} = params) when is_binary(page_size) do
    case Integer.parse(page_size) do
      {value, ""} when value > 0 -> Map.put(params, "page_size", value)
      _ -> params
    end
  end

  defp normalize_page_size(params), do: params

  defp audio_disposition(%{"download" => "1"}), do: "attachment"
  defp audio_disposition(_params), do: "inline"

  defp load_legacy_audio(audio_path) do
    absolute_path =
      if Path.type(audio_path) == :absolute do
        audio_path
      else
        Path.join(Audio.storage_dir(), audio_path)
      end

    File.read(absolute_path)
  end

  defp send_audio(conn, resource_id, disposition, content_type, audio, prefix) do
    filename = "#{prefix}-#{resource_id}.mp3"

    conn
    |> put_resp_content_type(content_type || "audio/mpeg")
    |> put_resp_header("content-disposition", "#{disposition}; filename=\"#{filename}\"")
    |> send_resp(200, audio)
  end

  defp serialize_generation(%Generation{} = generation) do
    %{
      id: generation.id,
      text: generation.text,
      voice_id: generation.voice_id,
      model_id: generation.model_id,
      output_format: generation.output_format,
      language_code: generation.language_code,
      quality_preset: generation.quality_preset,
      stability: generation.stability,
      similarity_boost: generation.similarity_boost,
      style: generation.style,
      speaker_boost: generation.speaker_boost,
      character_count: generation.character_count,
      content_type: generation.content_type,
      request_id: generation.request_id,
      remote_history_item_id: generation.remote_history_item_id,
      audio_url: ~p"/api/generations/#{generation.id}/audio",
      inserted_at: generation.inserted_at,
      updated_at: generation.updated_at
    }
  end
end
