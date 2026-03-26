defmodule PhoenixTts.ElevenLabs.Client do
  @behaviour PhoenixTts.ElevenLabs.ClientBehaviour

  def synthesize_speech(text, opts) do
    voice_id = Keyword.fetch!(opts, :voice_id)
    model_id = Keyword.fetch!(opts, :model_id)
    voice_settings = Keyword.get(opts, :voice_settings, %{})
    language_code = Keyword.get(opts, :language_code)
    output_format = Keyword.get(opts, :output_format)

    case api_key() do
      nil ->
        {:error, "Configure a variavel ELEVENLABS_API_KEY para gerar audios."}

      key ->
        request(key)
        |> Req.post(
          url: "/v1/text-to-speech/#{voice_id}",
          headers: [{"accept", "audio/mpeg"}],
          json:
            %{
              text: text,
              model_id: model_id,
              language_code: language_code,
              output_format: output_format,
              voice_settings: voice_settings
            }
            |> Enum.reject(fn {_key, value} -> is_nil(value) or value == %{} end)
            |> Map.new()
        )
        |> decode_audio_response()
    end
  end

  def list_voices(params \\ %{}) do
    case api_key() do
      nil ->
        {:error, "Configure a variavel ELEVENLABS_API_KEY para listar vozes."}

      key ->
        with {:ok, response} <- Req.get(request(key), url: "/v1/voices", params: params),
             {:ok, body} <- decode_json_body(response.body) do
          {:ok, parse_voices(body)}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def list_models do
    case api_key() do
      nil ->
        {:error, "Configure a variavel ELEVENLABS_API_KEY para listar modelos."}

      key ->
        with {:ok, response} <- Req.get(request(key), url: "/v1/models"),
             {:ok, body} <- decode_json_body(response.body) do
          {:ok,
           Enum.map(body, fn model ->
             %{
               id: model["model_id"],
               name: model["name"],
               description: model["description"],
               can_do_text_to_speech: model["can_do_text_to_speech"],
               maximum_text_length_per_request: model["maximum_text_length_per_request"]
             }
           end)}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def list_history(params \\ %{}) do
    case api_key() do
      nil ->
        {:error, "Configure a variavel ELEVENLABS_API_KEY para listar o histórico."}

      key ->
        with {:ok, response} <- Req.get(request(key), url: "/v1/history", params: params),
             {:ok, body} <- decode_json_body(response.body) do
          {:ok,
           %{
             items:
               Enum.map(body["history"] || [], fn item ->
                 %{
                   history_item_id: item["history_item_id"],
                   request_id: item["request_id"],
                   voice_id: item["voice_id"],
                   model_id: item["model_id"],
                   text: item["text"],
                   date_unix: item["date_unix"],
                   character_count_change_to: item["character_count_change_to"]
                 }
               end),
             has_more: body["has_more"] || false,
             last_history_item_id: body["last_history_item_id"]
           }}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def get_history_audio(history_item_id) do
    case api_key() do
      nil ->
        {:error, "Configure a variavel ELEVENLABS_API_KEY para ouvir ou baixar itens recentes."}

      key ->
        request(key)
        |> Req.get(url: "/v1/history/#{history_item_id}/audio", headers: [{"accept", "audio/mpeg"}])
        |> decode_history_audio_response()
    end
  end

  defp request(api_key) do
    Req.new(
      base_url: Application.fetch_env!(:phoenix_tts, :elevenlabs_base_url),
      headers: [
        {"xi-api-key", api_key},
        {"content-type", "application/json"}
      ],
      receive_timeout: 15_000
    )
  end

  defp decode_audio_response({:ok, %Req.Response{status: status, body: body, headers: headers}})
       when status in 200..299 do
    {:ok,
     %{
       audio: body,
       content_type: header_value(headers, "content-type") || "audio/mpeg",
       request_id: header_value(headers, "request-id"),
       history_item_id: header_value(headers, "history-item-id"),
       character_count: parse_integer_header(header_value(headers, "x-character-count"))
     }}
  end

  defp decode_audio_response({:ok, %Req.Response{status: _status, body: body}}) do
    with {:ok, decoded} <- decode_json_body(body) do
      {:error, decoded["detail"] || decoded["message"] || "Falha ao gerar audio na ElevenLabs."}
    else
      {:error, _reason} -> {:error, "Falha ao gerar audio na ElevenLabs."}
    end
  end

  defp decode_audio_response({:error, exception}) do
    {:error, Exception.message(exception)}
  end

  defp decode_history_audio_response({:ok, %Req.Response{status: status, body: body, headers: headers}})
       when status in 200..299 do
    {:ok,
     %{
       audio: body,
       content_type: header_value(headers, "content-type") || "audio/mpeg"
     }}
  end

  defp decode_history_audio_response({:ok, %Req.Response{status: _status, body: body}}) do
    with {:ok, decoded} <- decode_json_body(body) do
      {:error, decoded["detail"] || decoded["message"] || "Falha ao carregar audio do histórico."}
    else
      {:error, _reason} -> {:error, "Falha ao carregar audio do histórico."}
    end
  end

  defp decode_history_audio_response({:error, exception}) do
    {:error, Exception.message(exception)}
  end

  defp decode_json_body(body) when is_map(body), do: {:ok, body}
  defp decode_json_body(body) when is_list(body), do: {:ok, body}

  defp decode_json_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, "Resposta invalida da ElevenLabs."}
    end
  end

  defp header_value(headers, key) do
    headers
    |> Enum.find_value(fn
      {^key, [value | _]} -> sanitize_header(value)
      {^key, value} when is_binary(value) -> sanitize_header(value)
      _ -> nil
    end)
  end

  defp sanitize_header(value) do
    value
    |> String.split(";")
    |> List.first()
  end

  defp parse_integer_header(nil), do: nil

  defp parse_integer_header(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp parse_voices(body) do
    %{
      voices:
        Enum.map(body["voices"] || [], fn voice ->
          %{
            id: voice["voice_id"],
            name: voice["name"],
            category: voice["category"],
            labels: voice["labels"] || %{}
          }
        end),
      has_more: body["has_more"] || false,
      next_page_token: body["next_page_token"]
    }
  end

  defp api_key do
    Application.get_env(:phoenix_tts, :elevenlabs_api_key)
  end
end
