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

    def clone_instant_voice(name, files) do
      send(self(), {:clone_instant_voice, name, files})
      {:ok, %{voice_id: "voice_clone_123", name: name}}
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

    def get_subscription do
      {:ok,
       %{
         tier: "creator",
         status: "active",
         character_count: 1_250,
         character_limit: 10_000,
         next_character_count_reset_unix: 1_743_086_400
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

    def get_history_audio(_history_item_id) do
      {:ok, %{audio: "REMOTE-AUDIO", content_type: "audio/mpeg"}}
    end

    def get_subscription do
      FakeElevenLabsClient.get_subscription()
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
    assert html =~ "Studio"
    assert html =~ "Recentes"
    assert html =~ "Configuração"
    assert html =~ "Clone Voice"
    assert html =~ "0 / 5000 chars"
    assert html =~ "Idioma"
    assert html =~ "Português"
    assert html =~ "voice-combobox-input"
    assert html =~ "model-combobox-input"
    assert html =~ "language-combobox-input"
    assert html =~ "estimativa de gasto"
    assert html =~ "saldo após gerar"
    refute html =~ "Tokens restantes"
    refute html =~ "Itens recentes da ElevenLabs"
    refute html =~ "Escolha rápida"
    refute html =~ "Últimos áudios"
    assert html =~ "phx-disable-with=\"Gerando áudio...\""
  end

  test "config route renders the account balance section", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/config")

    assert html =~ "Configuração"
    assert html =~ "Tokens restantes"
    assert html =~ "Plano CREATOR"
    assert html =~ "8.750"
    refute html =~ "voice-combobox-input"
    refute html =~ "Itens recentes da ElevenLabs"
    refute html =~ "Navegação rápida"
  end

  test "clone route renders the voice cloning form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/clone")

    assert html =~ "Instant Voice Clone"
    assert html =~ "Nome da voz"
    assert html =~ "Amostras de áudio"
    assert html =~ "Enviar para clonagem"
    refute html =~ "voice-combobox-input"
  end

  test "clone route uploads samples and shows the new voice id", %{conn: conn} do
    sample_path =
      Path.join(System.tmp_dir!(), "live-clone-sample-#{System.unique_integer([:positive])}.mp3")

    File.write!(sample_path, "VOICE-SAMPLE")

    on_exit(fn -> File.rm(sample_path) end)

    {:ok, view, _html} = live(conn, ~p"/clone")

    upload =
      file_input(view, "#clone-form", :samples, [
        %{
          last_modified: 1_743_000_000_000,
          name: "sample-1.mp3",
          content: File.read!(sample_path),
          type: "audio/mpeg"
        }
      ])

    assert render_upload(upload, "sample-1.mp3") =~ "sample-1.mp3"

    html =
      view
      |> form("#clone-form", clone_voice: %{"name" => "Minha Voz Clone"})
      |> render_submit()

    assert html =~ "Voice clone criada com sucesso."
    assert html =~ "voice_clone_123"
  end

  test "recentes route focuses on remote and local history", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/recentes")

    assert html =~ "Itens recentes da ElevenLabs"
    assert html =~ "Texto remoto da API"
    assert html =~ "ouvir agora"
    assert html =~ "Carregar mais"
    assert html =~ "Narradora BR"
    assert html =~ "Escolha rápida"
    assert html =~ "Últimos áudios"
    refute html =~ "voice-combobox-input"
    refute html =~ "Tokens restantes"
  end

  test "submitting the form creates an audio entry and keeps the studio focused on generation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    _html =
      view
      |> element("#language-combobox-input")
      |> render_keyup(%{"field" => "language", "value" => "en"})

    _html =
      view
      |> element("button[phx-click=\"select_combobox\"][phx-value-field=\"language\"][phx-value-option=\"en\"]")
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
    assert html =~ "Narradora BR"
    assert html =~ "Inglês"
    assert html =~ "última configuração foi mantida"
    refute html =~ "Últimos áudios"
    refute html =~ "audio-player"
  end

  test "renders remote history items even when text is nil", %{conn: conn} do
    Application.put_env(
      :phoenix_tts,
      :elevenlabs_client,
      FakeElevenLabsClientWithoutHistoryText
    )

    {:ok, _view, html} = live(conn, ~p"/recentes")

    assert html =~ "Sem texto disponível"
    assert html =~ "18 chars"
  end

  test "loads the next page of recent ElevenLabs items", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/recentes")

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
    {:ok, view, html} = live(conn, ~p"/recentes")

    assert html =~ "selecionada"
    assert html =~ "Narradora BR"

    html =
      view
      |> element("button[phx-value-voice_id=\"voice_relax\"]")
      |> render_click()

    assert html =~ "Voz Relax"
    assert html =~ "voice_relax"
    refute html =~ "phx-value-voice_id=\"voice_relax\" class=\"block w-full rounded-[1.4rem] border p-4 text-left transition border-white/10"
  end

  test "recent voices search filters the quick choice list", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/recentes")

    assert html =~ "Narradora BR"
    assert html =~ "Voz Relax"

    html =
      view
      |> element("#recent-voice-search")
      |> render_keyup(%{"value" => "relax"})

    assert html =~ "value=\"relax\""
    assert html =~ "Voz Relax"
    refute html =~ "Narradora BR"
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

  test "combobox does not render fallback text as the input value", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    refute html =~ "value=\"Sem voz selecionada\""
    refute html =~ "value=\"Sem modelo selecionado\""
    refute html =~ "value=\"Idioma automático\""
  end

  test "recentes route shows the generated item with reuse action", %{conn: conn} do
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

    {:ok, recentes_view, _html} = live(conn, ~p"/recentes")

    html = render(recentes_view)

    assert html =~ "Últimos áudios"
    assert html =~ "Narradora BR"
    assert html =~ "MP3 44.1kHz / 128kbps"
    assert html =~ "usar novamente esta configuração"
    assert html =~ "req_live_1"
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
