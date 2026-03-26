defmodule PhoenixTts.ElevenLabs.ClientTest do
  use ExUnit.Case, async: true

  alias PhoenixTts.ElevenLabs.Client

  setup do
    bypass = Bypass.open()

    Application.put_env(:phoenix_tts, :elevenlabs_api_key, "test-key")
    Application.put_env(:phoenix_tts, :elevenlabs_base_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Application.delete_env(:phoenix_tts, :elevenlabs_api_key)
      Application.delete_env(:phoenix_tts, :elevenlabs_base_url)
    end)

    %{bypass: bypass}
  end

  test "synthesize_speech posts the expected payload and returns audio with metadata", %{
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/v1/text-to-speech/voice_br", fn conn ->
      assert {"xi-api-key", "test-key"} in conn.req_headers
      assert {"accept", "audio/mpeg"} in conn.req_headers

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["text"] == "Texto para narrar"
      assert payload["model_id"] == "eleven_multilingual_v2"
      assert payload["language_code"] == "pt"
      assert payload["output_format"] == "mp3_44100_128"
      assert payload["voice_settings"]["stability"] == 0.45
      assert payload["voice_settings"]["similarity_boost"] == 0.8

      conn
      |> Plug.Conn.put_resp_content_type("audio/mpeg")
      |> Plug.Conn.put_resp_header("request-id", "req_123")
      |> Plug.Conn.put_resp_header("history-item-id", "hist_123")
      |> Plug.Conn.put_resp_header("x-character-count", "17")
      |> Plug.Conn.resp(200, "FAKE-MP3")
    end)

    assert {:ok,
            %{
              audio: "FAKE-MP3",
              content_type: "audio/mpeg",
              request_id: "req_123",
              history_item_id: "hist_123",
              character_count: 17
            }} =
             Client.synthesize_speech("Texto para narrar",
               voice_id: "voice_br",
               model_id: "eleven_multilingual_v2",
               language_code: "pt",
               output_format: "mp3_44100_128",
               voice_settings: %{stability: 0.45, similarity_boost: 0.8}
             )
  end

  test "list_voices parses the ElevenLabs response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/voices", fn conn ->
      assert {"xi-api-key", "test-key"} in conn.req_headers
      assert conn.query_string =~ "page_size=25"
      assert conn.query_string =~ "search=br"

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          voices: [
            %{
              "voice_id" => "voice_br",
              "name" => "Narradora BR",
              "labels" => %{"accent" => "pt-BR", "gender" => "female"}
            }
          ],
          has_more: false,
          next_page_token: nil
        })
      )
    end)

    assert {:ok,
            %{
              voices: [
                %{
                  id: "voice_br",
                  name: "Narradora BR",
                  labels: %{"accent" => "pt-BR", "gender" => "female"}
                }
              ],
              has_more: false,
              next_page_token: nil
            }} = Client.list_voices(%{page_size: 25, search: "br"})
  end

  test "list_models returns only the parsed catalog", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/models", fn conn ->
      assert {"xi-api-key", "test-key"} in conn.req_headers

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!([
          %{
            "model_id" => "eleven_multilingual_v2",
            "name" => "Eleven Multilingual v2",
            "description" => "Long-form multilingual speech",
            "can_do_text_to_speech" => true,
            "maximum_text_length_per_request" => 10_000
          }
        ])
      )
    end)

    assert {:ok,
            [
              %{
                id: "eleven_multilingual_v2",
                name: "Eleven Multilingual v2",
                description: "Long-form multilingual speech",
                can_do_text_to_speech: true,
                maximum_text_length_per_request: 10_000
              }
            ]} = Client.list_models()
  end

  test "clone_instant_voice posts multipart audio samples and returns the new voice id", %{
    bypass: bypass
  } do
    sample_path =
      Path.join(System.tmp_dir!(), "clone-sample-#{System.unique_integer([:positive])}.mp3")

    File.write!(sample_path, "FAKE-AUDIO-SAMPLE")

    on_exit(fn -> File.rm(sample_path) end)

    Bypass.expect_once(bypass, "POST", "/v1/voices/add", fn conn ->
      assert {"xi-api-key", "test-key"} in conn.req_headers
      assert {"content-type", content_type} = List.keyfind(conn.req_headers, "content-type", 0)
      assert String.starts_with?(content_type, "multipart/form-data;")

      conn = Plug.Conn.fetch_query_params(conn)
      conn = Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:multipart]))

      assert conn.body_params["name"] == "My Voice Clone"

      [
        %Plug.Upload{
          filename: "clone-sample-1.mp3",
          content_type: "audio/mpeg",
          path: upload_path
        }
      ] =
        List.wrap(conn.body_params["files"])

      assert File.read!(upload_path) == "FAKE-AUDIO-SAMPLE"

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "voice_id" => "voice_clone_123",
          "name" => "My Voice Clone"
        })
      )
    end)

    assert {:ok, %{voice_id: "voice_clone_123", name: "My Voice Clone"}} =
             Client.clone_instant_voice("My Voice Clone", [
               %{path: sample_path, filename: "clone-sample-1.mp3", content_type: "audio/mpeg"}
             ])
  end

  test "clone_instant_voice also accepts consumed upload bytes", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1/voices/add", fn conn ->
      assert {"xi-api-key", "test-key"} in conn.req_headers

      conn = Plug.Conn.fetch_query_params(conn)
      conn = Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:multipart]))

      assert conn.body_params["name"] == "Binary Clone"

      [%Plug.Upload{filename: "sample.ogg", content_type: "audio/ogg", path: upload_path}] =
        List.wrap(conn.body_params["files"])

      assert File.read!(upload_path) == "BINARY-UPLOAD"

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "voice_id" => "voice_clone_binary",
          "name" => "Binary Clone"
        })
      )
    end)

    assert {:ok, %{voice_id: "voice_clone_binary", name: "Binary Clone"}} =
             Client.clone_instant_voice("Binary Clone", [
               %{binary: "BINARY-UPLOAD", filename: "sample.ogg", content_type: "audio/ogg"}
             ])
  end

  test "list_history parses the generated items response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/history", fn conn ->
      assert {"xi-api-key", "test-key"} in conn.req_headers
      assert conn.query_string =~ "page_size=5"
      assert conn.query_string =~ "voice_id=voice_br"

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          history: [
            %{
              "history_item_id" => "hist_123",
              "request_id" => "req_123",
              "voice_id" => "voice_br",
              "model_id" => "eleven_multilingual_v2",
              "text" => "Texto remoto",
              "date_unix" => 1_743_000_000,
              "character_count_change_from" => 0,
              "character_count_change_to" => 12
            }
          ],
          has_more: false,
          last_history_item_id: "hist_123"
        })
      )
    end)

    assert {:ok,
            %{
              items: [
                %{
                  history_item_id: "hist_123",
                  request_id: "req_123",
                  voice_id: "voice_br",
                  model_id: "eleven_multilingual_v2",
                  text: "Texto remoto",
                  date_unix: 1_743_000_000,
                  character_count_change_to: 12
                }
              ],
              has_more: false,
              last_history_item_id: "hist_123"
            }} = Client.list_history(%{page_size: 5, voice_id: "voice_br"})
  end

  test "get_history_audio returns the audio bytes for a history item", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/history/hist_123/audio", fn conn ->
      assert {"xi-api-key", "test-key"} in conn.req_headers
      assert {"accept", "audio/mpeg"} in conn.req_headers

      conn
      |> Plug.Conn.put_resp_content_type("audio/mpeg")
      |> Plug.Conn.resp(200, "REMOTE-MP3")
    end)

    assert {:ok, %{audio: "REMOTE-MP3", content_type: "audio/mpeg"}} =
             Client.get_history_audio("hist_123")
  end

  test "get_subscription returns the current account usage", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1/user", fn conn ->
      assert {"xi-api-key", "test-key"} in conn.req_headers

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          subscription: %{
            tier: "creator",
            status: "active",
            character_count: 1_250,
            character_limit: 10_000,
            next_character_count_reset_unix: 1_743_086_400
          }
        })
      )
    end)

    assert {:ok,
            %{
              tier: "creator",
              status: "active",
              character_count: 1_250,
              character_limit: 10_000,
              next_character_count_reset_unix: 1_743_086_400
            }} = Client.get_subscription()
  end
end
