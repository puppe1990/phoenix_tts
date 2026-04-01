defmodule PhoenixTtsWeb.AudioApiControllerTest do
  use PhoenixTtsWeb.ConnCase, async: false

  alias PhoenixTts.Audio.Generation
  alias PhoenixTts.Repo

  defmodule FakeElevenLabsClient do
    def synthesize_speech(text, opts) do
      send(self(), {:synthesize_speech, text, opts})

      {:ok,
       %{
         audio: "API-MP3-DATA",
         content_type: "audio/mpeg",
         request_id: "req_api_123",
         history_item_id: "hist_api_123",
         character_count: 48
       }}
    end

    def list_voices(_params \\ %{}) do
      {:ok,
       %{
         voices: [
           %{
             id: "voice_api",
             name: "API Voice",
             category: "premade",
             labels: %{"accent" => "pt-BR"}
           }
         ]
       }}
    end

    def list_models do
      {:ok,
       [
         %{
           id: "eleven_multilingual_v2",
           name: "Eleven Multilingual v2",
           can_do_text_to_speech: true
         }
       ]}
    end

    def get_subscription do
      {:ok,
       %{
         tier: "creator",
         status: "active",
         character_count: 200,
         character_limit: 2_000,
         next_character_count_reset_unix: 1_743_086_400
       }}
    end

    def list_history(params \\ %{}) do
      send(self(), {:list_history, params})

      {:ok,
       %{
         items: [%{history_item_id: "hist_remote_1", request_id: "req_remote_1"}],
         has_more: false,
         last_history_item_id: "hist_remote_1"
       }}
    end

    def get_history_audio(history_item_id) do
      send(self(), {:get_history_audio, history_item_id})
      {:ok, %{audio: "REMOTE-AUDIO", content_type: "audio/mpeg"}}
    end
  end

  setup do
    Application.put_env(:phoenix_tts, :elevenlabs_client, FakeElevenLabsClient)
    Application.put_env(:phoenix_tts, :api_auth_token, "test-api-token")
    Application.put_env(:phoenix_tts, :api_allowed_origins, ["http://localhost:3000"])

    on_exit(fn ->
      Application.delete_env(:phoenix_tts, :elevenlabs_client)
      Application.delete_env(:phoenix_tts, :api_auth_token)
      Application.delete_env(:phoenix_tts, :api_allowed_origins)
    end)

    :ok
  end

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  test "lists stored generations", %{conn: conn} do
    generation =
      %Generation{}
      |> Generation.persistence_changeset(%{
        text: "Texto local para exposição via API.",
        voice_id: "voice_api",
        model_id: "eleven_multilingual_v2",
        output_format: "mp3_44100_128",
        language_code: "pt",
        audio_binary: "LOCAL-MP3",
        character_count: 34,
        content_type: "audio/mpeg"
      })
      |> Repo.insert!()

    response =
      conn
      |> api_conn()
      |> get(~p"/api/generations")
      |> json_response(200)

    assert [%{"id" => id, "audio_url" => audio_url}] = response["data"]
    assert id == generation.id
    assert audio_url == "/api/generations/#{generation.id}/audio"
  end

  test "creates a generation and returns the payload", %{conn: conn} do
    params = %{
      "text" => "Uma resposta de áudio pronta para ser consumida por outro sistema.",
      "voice_id" => "voice_api",
      "model_id" => "eleven_multilingual_v2",
      "output_format" => "mp3_44100_128",
      "language_code" => "pt"
    }

    response =
      conn
      |> api_conn()
      |> post(~p"/api/generations", params)
      |> json_response(201)

    assert %{
             "voice_id" => "voice_api",
             "request_id" => "req_api_123",
             "remote_history_item_id" => "hist_api_123",
             "audio_url" => audio_url
           } = response["data"]

    assert audio_url =~ ~r|^/api/generations/\d+/audio$|

    assert_received {:synthesize_speech,
                     "Uma resposta de áudio pronta para ser consumida por outro sistema.", _opts}
  end

  test "returns validation errors on invalid generation payload", %{conn: conn} do
    response =
      conn
      |> api_conn()
      |> post(~p"/api/generations", %{"text" => "", "voice_id" => "", "model_id" => ""})
      |> json_response(422)

    assert response["errors"]["text"] == ["can't be blank"]
    assert response["errors"]["voice_id"] == ["can't be blank"]
    assert response["errors"]["model_id"] == ["can't be blank"]
  end

  test "exposes voices, models and subscription overview", %{conn: conn} do
    voices =
      conn
      |> api_conn()
      |> get(~p"/api/voices")
      |> json_response(200)

    models =
      build_conn()
      |> api_conn()
      |> get(~p"/api/models")
      |> json_response(200)

    subscription =
      build_conn()
      |> api_conn()
      |> get(~p"/api/subscription")
      |> json_response(200)

    assert [%{"id" => "voice_api"}] = voices["data"]
    assert [%{"id" => "eleven_multilingual_v2"}] = models["data"]
    assert subscription["data"]["remaining_credits"] == 1_800
  end

  test "passes history pagination params through the API", %{conn: conn} do
    response =
      conn
      |> api_conn()
      |> get(~p"/api/history?page_size=5&start_after_history_item_id=hist_remote_0")
      |> json_response(200)

    assert [%{"history_item_id" => "hist_remote_1"}] = response["data"]["items"]

    assert_received {:list_history,
                     %{
                       "page_size" => 5,
                       "start_after_history_item_id" => "hist_remote_0"
                     }}
  end

  test "streams generation audio from the api", %{conn: conn} do
    generation =
      %Generation{}
      |> Generation.persistence_changeset(%{
        text: "Texto com áudio embutido.",
        voice_id: "voice_api",
        model_id: "eleven_multilingual_v2",
        output_format: "mp3_44100_128",
        language_code: "pt",
        audio_binary: "LOCAL-API-MP3",
        character_count: 24,
        content_type: "audio/mpeg"
      })
      |> Repo.insert!()

    conn =
      conn
      |> api_conn()
      |> get(~p"/api/generations/#{generation.id}/audio?download=1")

    assert response(conn, 200) == "LOCAL-API-MP3"

    assert get_resp_header(conn, "content-disposition") == [
             "attachment; filename=\"generation-#{generation.id}.mp3\""
           ]
  end

  test "streams remote history audio from the api", %{conn: conn} do
    conn =
      conn
      |> api_conn()
      |> get(~p"/api/history/hist_remote_1/audio")

    assert response(conn, 200) == "REMOTE-AUDIO"
    assert_received {:get_history_audio, "hist_remote_1"}
  end

  test "rejects requests without bearer token", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/voices")
      |> json_response(401)

    assert response == %{"error" => "unauthorized"}
  end

  test "responds to cors preflight for allowed origins", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "http://localhost:3000")
      |> put_req_header("access-control-request-method", "POST")
      |> options(~p"/api/generations")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:3000"]
    assert get_resp_header(conn, "access-control-allow-methods") == ["GET,POST,OPTIONS"]
  end
end
