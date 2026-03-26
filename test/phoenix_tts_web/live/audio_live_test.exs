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

    def list_history(params \\ %{}) do
      case Map.get(params, :start_after_history_item_id) || Map.get(params, "start_after_history_item_id") do
        "hist_remote_1" ->
          {:ok,
           %{
             items: [
               %{
                 history_item_id: "hist_remote_2",
                 request_id: "req_remote_2",
                 voice_id: "voice_relax",
                 model_id: "eleven_flash_v2_5",
                 text: "Texto remoto da API 2",
                 date_unix: 1_743_000_100,
                 character_count_change_to: 24
               }
             ],
             has_more: false,
             last_history_item_id: "hist_remote_2"
           }}

        _ ->
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
             has_more: true,
             last_history_item_id: "hist_remote_1"
           }}
      end
    end

    def get_history_audio(_history_item_id) do
      {:ok, %{audio: "REMOTE-AUDIO", content_type: "audio/mpeg"}}
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

    def get_history_audio(_history_item_id) do
      {:ok, %{audio: "REMOTE-AUDIO", content_type: "audio/mpeg"}}
    end
  end

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "phoenix-tts-live-#{System.unique_integer([:positive])}")

    Application.put_env(:phoenix_tts, :elevenlabs_client, FakeElevenLabsClient)
    Application.put_env(:phoenix_tts, :audio_storage_dir, tmp_dir)
    Application.put_env(:phoenix_tts, :elevenlabs_api_key, "test-key")

    on_exit(fn ->
      File.rm_rf(tmp_dir)
      Application.delete_env(:phoenix_tts, :elevenlabs_client)
      Application.delete_env(:phoenix_tts, :audio_storage_dir)
      Application.delete_env(:phoenix_tts, :elevenlabs_api_key)
    end)

    :ok
  end

  test "renders the studio and the available voices", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "ElevenLabs Audio Studio"
    assert html =~ "Narradora BR"
    assert html =~ "clique para usar"
    assert html =~ "Texto remoto da API"
    assert html =~ "Nenhum áudio gerado ainda"
    assert html =~ "0 / 5000 chars"
    assert html =~ "Idioma"
    assert html =~ "Português"
    assert html =~ "voice-combobox-input"
    assert html =~ "model-combobox-input"
    assert html =~ "language-combobox-input"
    assert html =~ "ouvir agora"
    assert html =~ "baixar áudio"
    assert html =~ "Carregar mais"
    assert html =~ "phx-disable-with=\"Gerando áudio...\""
  end

  test "submitting the form creates an audio entry and renders the player", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    _html =
      view
      |> element("#language-combobox-input")
      |> render_keyup(%{"field" => "language", "value" => "en"})

    _html =
      view
      |> element("button[phx-click=\"select_combobox\"][phx-value-field=\"language\"][phx-value-value=\"en\"]")
      |> render_click()

    params = %{
      "text" => "Escreva um áudio curto para aliviar a sensação de peso antes de dormir.",
      "voice_id" => "voice_br",
      "model_id" => "eleven_multilingual_v2",
      "output_format" => "mp3_44100_128",
      "language_code" => "en"
    }

    html =
      view
      |> form("#tts-form", audio_generation: params)
      |> render_submit()

    assert html =~ "Áudio gerado com sucesso."
    assert html =~ "audio-player"
    assert html =~ "Narradora BR"
    assert html =~ "req_live_1"
    assert html =~ "MP3 44.1kHz / 128kbps"
    assert html =~ "Inglês"
    assert html =~ "baixar mp3"
    assert html =~ "última configuração foi mantida"
    assert html =~ "usar novamente esta configuração"
  end

  test "renders remote history items even when text is nil", %{conn: conn} do
    Application.put_env(
      :phoenix_tts,
      :elevenlabs_client,
      FakeElevenLabsClientWithoutHistoryText
    )

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Sem texto disponível"
    assert html =~ "18 chars"
  end

  test "loads the next page of recent ElevenLabs items", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Texto remoto da API"
    assert html =~ "Carregar mais"

    html =
      view
      |> element("button[phx-click=\"load_more_remote_history\"]")
      |> render_click()

    assert html =~ "Texto remoto da API"
    assert html =~ "Texto remoto da API 2"
    refute html =~ "Carregar mais"
  end

  test "clicking a voice card selects it in the form", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "selecionada"
    assert html =~ "value=\"Narradora BR\""

    html =
      view
      |> element("button[phx-value-voice_id=\"voice_relax\"]")
      |> render_click()

    assert html =~ "Voz Relax"
    assert html =~ "value=\"Voz Relax\""
  end

  test "combobox inputs filter voice, model and language options", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Narradora BR"
    assert html =~ "value=\"Eleven Multilingual v2\""
    assert html =~ "value=\"Português\""

    html =
      view
      |> element("#voice-combobox-input")
      |> render_keyup(%{"field" => "voice", "value" => "relax"})

    assert html =~ "value=\"relax\""
    assert html =~ "Voz Relax"
    assert html =~ "voice_relax"

    html =
      view
      |> element("#model-combobox-input")
      |> render_keyup(%{"field" => "model", "value" => "flash"})

    assert html =~ "value=\"flash\""

    html =
      view
      |> element("#language-combobox-input")
      |> render_keyup(%{"field" => "language", "value" => "ja"})

    assert html =~ "value=\"ja\""
    assert html =~ "Japonês"
    refute html =~ "Português</div><div class=\"mt-1 text-xs uppercase tracking-[0.14em] text-white/35\">pt"
  end

  test "reusing a generation reapplies its configuration", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    params = %{
      "text" => "Escreva um áudio curto para aliviar a sensação de peso antes de dormir.",
      "voice_id" => "voice_br",
      "model_id" => "eleven_multilingual_v2",
      "output_format" => "mp3_44100_128",
      "language_code" => "pt"
    }

    _html =
      view
      |> form("#tts-form", audio_generation: params)
      |> render_submit()

    html =
      view
      |> element("button[phx-click=\"reuse_generation\"]")
      |> render_click()

    assert html =~ "Configuração reaplicada. Ajuste o texto e gere novamente."
    assert html =~ "Voice ID atual"
  end

  test "disables generation and explains setup when api key is missing", %{conn: conn} do
    Application.delete_env(:phoenix_tts, :elevenlabs_api_key)
    Application.put_env(:phoenix_tts, :elevenlabs_client, PhoenixTts.ElevenLabs.Client)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "ElevenLabs não configurado"
    assert html =~ "ELEVENLABS_API_KEY"
    assert html =~ "disabled"
  end
end
