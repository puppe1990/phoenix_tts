defmodule PhoenixTtsWeb.AudioLiveTest do
  use PhoenixTtsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defmodule FakeElevenLabsClient do
    def synthesize_speech(_text, _opts) do
      {:ok,
       %{
         audio: "FAKE-LIVEVIEW-MP3",
         content_type: "audio/mpeg",
         request_id: "req_live_1",
         history_item_id: "hist_live_1",
         character_count: 72
       }}
    end

    def list_voices(_params \\ %{}) do
      {:ok,
       %{
         voices: [
           %{
             id: "voice_br",
             name: "Narradora BR",
             category: "premade",
             labels: %{"accent" => "pt-BR"}
           },
           %{
             id: "voice_relax",
             name: "Voz Relax",
             category: "cloned",
             labels: %{"accent" => "pt-BR"}
           }
         ],
         has_more: false,
         next_page_token: nil
       }}
    end

    def list_models do
      {:ok,
       [
         %{
           id: "eleven_multilingual_v2",
           name: "Eleven Multilingual v2",
           description: "Long-form multilingual speech",
           can_do_text_to_speech: true,
           maximum_text_length_per_request: 10_000
         },
         %{
           id: "eleven_flash_v2_5",
           name: "Eleven Flash v2.5",
           description: "Low latency speech",
           can_do_text_to_speech: true,
           maximum_text_length_per_request: 40_000
         }
       ]}
    end

    def list_history(_params \\ %{}) do
      {:ok,
       %{
         items: [
           %{
             history_item_id: "hist_remote_1",
             request_id: "req_remote_1",
             voice_id: "voice_br",
             model_id: "eleven_multilingual_v2",
             text: "Texto remoto da API",
             date_unix: 1_743_000_000,
             character_count_change_to: 18
           }
         ],
         has_more: false,
         last_history_item_id: "hist_remote_1"
       }}
    end
  end

  defmodule FakeElevenLabsClientWithoutHistoryText do
    def synthesize_speech(_text, _opts) do
      {:ok,
       %{
         audio: "FAKE-LIVEVIEW-MP3",
         content_type: "audio/mpeg",
         request_id: "req_live_1",
         history_item_id: "hist_live_1",
         character_count: 72
       }}
    end

    def list_voices(_params \\ %{}) do
      FakeElevenLabsClient.list_voices()
    end

    def list_models do
      FakeElevenLabsClient.list_models()
    end

    def list_history(_params \\ %{}) do
      {:ok,
       %{
         items: [
           %{
             history_item_id: "hist_remote_nil",
             request_id: "req_remote_nil",
             voice_id: "voice_br",
             model_id: "eleven_multilingual_v2",
             text: nil,
             date_unix: 1_743_000_000,
             character_count_change_to: 18
           }
         ],
         has_more: false,
         last_history_item_id: "hist_remote_nil"
       }}
    end
  end

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "phoenix-tts-live-#{System.unique_integer([:positive])}")

    Application.put_env(:phoenix_tts, :elevenlabs_client, FakeElevenLabsClient)
    Application.put_env(:phoenix_tts, :audio_storage_dir, tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
      Application.delete_env(:phoenix_tts, :elevenlabs_client)
      Application.delete_env(:phoenix_tts, :audio_storage_dir)
    end)

    :ok
  end

  test "renders the studio and the available voices", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "ElevenLabs Audio Studio"
    assert html =~ "Narradora BR"
    assert html =~ "premade"
    assert html =~ "Texto remoto da API"
    assert html =~ "Nenhum áudio gerado ainda"
  end

  test "submitting the form creates an audio entry and renders the player", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    params = %{
      "text" => "Escreva um áudio curto para aliviar a sensação de peso antes de dormir.",
      "voice_id" => "voice_br",
      "model_id" => "eleven_multilingual_v2",
      "output_format" => "mp3_44100_128",
      "language_code" => "pt"
    }

    html =
      view
      |> form("#tts-form", audio_generation: params)
      |> render_submit()

    assert html =~ "Áudio gerado com sucesso."
    assert html =~ "audio-player"
    assert html =~ "voice_br"
    assert html =~ "req_live_1"
    assert html =~ "mp3_44100_128"
    assert html =~ "baixar mp3"
  end

  test "renders remote history items even when text is nil", %{conn: conn} do
    Application.put_env(
      :phoenix_tts,
      :elevenlabs_client,
      FakeElevenLabsClientWithoutHistoryText
    )

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Sem texto disponível"
    assert html =~ "hist_remote_nil"
  end
end
