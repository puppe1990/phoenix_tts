defmodule PhoenixTts.AudioTest do
  use PhoenixTts.DataCase, async: false

  alias PhoenixTts.Audio
  alias PhoenixTts.Audio.Generation
  alias PhoenixTts.Audio.Voice

  defmodule FakeElevenLabsClient do
    def synthesize_speech("timeout case", _opts) do
      {:error, "timeout"}
    end

    def synthesize_speech(text, opts) do
      send(self(), {:synthesize_speech, text, opts})

      {:ok,
       %{
         audio: "FAKE-MP3-DATA",
         content_type: "audio/mpeg",
         request_id: "req_local_123",
         history_item_id: "hist_local_123",
         character_count: 64
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
         }
       ]}
    end

    def clone_instant_voice(name, files) do
      send(self(), {:clone_instant_voice, name, files})
      {:ok, %{voice_id: "voice_clone_123", name: name}}
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

    def list_history(params \\ %{}) do
      case Map.get(params, :start_after_history_item_id) ||
             Map.get(params, "start_after_history_item_id") do
        "hist_remote_1" ->
          {:ok,
           %{
             items: [
               %{
                 history_item_id: "hist_remote_2",
                 request_id: "req_remote_2",
                 voice_id: "voice_br",
                 model_id: "eleven_multilingual_v2",
                 text: "Texto remoto 2",
                 date_unix: 1_743_000_100,
                 character_count_change_to: 13
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
                 text: "Texto remoto",
                 date_unix: 1_743_000_000,
                 character_count_change_to: 12
               }
             ],
             has_more: true,
             last_history_item_id: "hist_remote_1"
           }}
      end
    end
  end

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "phoenix-tts-audio-#{System.unique_integer([:positive])}")

    Application.put_env(:phoenix_tts, :elevenlabs_client, FakeElevenLabsClient)
    Application.put_env(:phoenix_tts, :audio_storage_dir, tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
      Application.delete_env(:phoenix_tts, :elevenlabs_client)
      Application.delete_env(:phoenix_tts, :audio_storage_dir)
    end)

    :ok
  end

  test "create_generation persists the audio metadata and writes the mp3 file" do
    attrs = %{
      "text" => "Uma metáfora curta para destravar o começo do dia com calma e foco.",
      "voice_id" => "voice_br",
      "model_id" => "eleven_multilingual_v2",
      "output_format" => "mp3_44100_128",
      "language_code" => "pt"
    }

    assert {:ok, %Generation{} = generation} = Audio.create_generation(attrs)

    assert_received {:synthesize_speech,
                     "Uma metáfora curta para destravar o começo do dia com calma e foco.", opts}

    assert opts[:voice_id] == "voice_br"
    assert opts[:model_id] == "eleven_multilingual_v2"
    assert opts[:output_format] == "mp3_44100_128"
    assert opts[:language_code] == "pt"
    assert generation.voice_id == "voice_br"
    assert generation.model_id == "eleven_multilingual_v2"
    assert generation.output_format == "mp3_44100_128"
    assert generation.language_code == "pt"
    assert generation.request_id == "req_local_123"
    assert generation.remote_history_item_id == "hist_local_123"
    assert generation.character_count == 64
    assert generation.content_type == "audio/mpeg"
    assert generation.audio_path =~ ~r/^generated\/.+\.mp3$/
    assert File.read!(Path.join(Audio.storage_dir(), generation.audio_path)) == "FAKE-MP3-DATA"

    generation_id = generation.id
    assert [%Generation{id: ^generation_id}] = Audio.list_generations()
  end

  test "create_generation validates required fields before calling ElevenLabs" do
    assert {:error, changeset} =
             Audio.create_generation(%{
               "text" => "",
               "voice_id" => "",
               "model_id" => "",
               "output_format" => "",
               "language_code" => ""
             })

    assert %{
             text: ["can't be blank"],
             voice_id: ["can't be blank"],
             model_id: ["can't be blank"]
           } = errors_on(changeset)

    refute_received {:synthesize_speech, _, _}
  end

  test "create_generation splits long text into two ElevenLabs requests and merges the audio" do
    long_text =
      String.duplicate("Parágrafo terapêutico com pausa.\n\n", 210)
      |> String.slice(0, 6_670)

    assert String.length(long_text) == 6_670

    assert {:ok, %Generation{} = generation} =
             Audio.create_generation(%{
               "text" => long_text,
               "voice_id" => "voice_br",
               "model_id" => "eleven_multilingual_v2",
               "output_format" => "mp3_44100_128",
               "language_code" => "pt"
             })

    assert_received {:synthesize_speech, first_chunk, _opts}
    assert_received {:synthesize_speech, second_chunk, _opts}
    assert String.length(first_chunk) <= 5_000
    assert String.length(second_chunk) <= 5_000
    assert String.length(first_chunk) + String.length(second_chunk) <= 6_670
    assert generation.character_count == 128
    assert generation.request_id == "req_local_123, req_local_123"
    assert generation.remote_history_item_id == "hist_local_123, hist_local_123"

    assert File.read!(Path.join(Audio.storage_dir(), generation.audio_path)) ==
             "FAKE-MP3-DATAFAKE-MP3-DATA"
  end

  test "create_generation turns timeout into an actionable runtime error" do
    assert {:error, changeset} =
             Audio.create_generation(%{
               "text" => "timeout case",
               "voice_id" => "voice_br",
               "model_id" => "eleven_multilingual_v2",
               "output_format" => "mp3_44100_128",
               "language_code" => "pt"
             })

    assert %{
             runtime: [
               "A ElevenLabs demorou mais que o limite local. O áudio pode ter sido gerado; confira Itens recentes."
             ]
           } =
             errors_on(changeset)
  end

  test "create_generation rejects text above two operational chunks" do
    assert {:error, changeset} =
             Audio.create_generation(%{
               "text" => String.duplicate("a", 10_001),
               "voice_id" => "voice_br",
               "model_id" => "eleven_multilingual_v2",
               "output_format" => "mp3_44100_128",
               "language_code" => "pt"
             })

    assert %{text: ["should be at most 10000 character(s)"]} = errors_on(changeset)
    refute_received {:synthesize_speech, _, _}
  end

  test "catalog helpers expose remote voices, models, history and endpoint map" do
    assert [%{id: "voice_br", category: "premade"}] = Audio.available_voices()
    assert [%{id: "voice_br", category: "premade"}] = Audio.list_voices()
    assert [%Voice{voice_id: "voice_br", category: "premade"}] = Repo.all(Voice)
    assert [%{id: "eleven_multilingual_v2"}] = Audio.available_models()
    assert [%{history_item_id: "hist_remote_1"}] = Audio.remote_history()

    assert {:ok, %{has_more: true, last_history_item_id: "hist_remote_1"}} =
             Audio.remote_history_page()

    assert {:ok, %{items: [%{history_item_id: "hist_remote_2"}]}} =
             Audio.remote_history_page(%{start_after_history_item_id: "hist_remote_1"})

    assert {:ok, %{remaining_credits: 8_750, total_credits: 10_000, used_credits: 1_250}} =
             Audio.subscription_overview()

    endpoint_slugs =
      Audio.endpoint_catalog()
      |> Enum.map(& &1.slug)

    assert "text-to-speech-convert" in endpoint_slugs
    assert "voices-search" in endpoint_slugs
    assert "models-list" in endpoint_slugs
    assert "history-list" in endpoint_slugs
    assert "voices-clone-instant" in endpoint_slugs
  end

  test "clone_voice validates input and sends the uploaded samples to ElevenLabs" do
    sample_path =
      Path.join(System.tmp_dir!(), "audio-clone-sample-#{System.unique_integer([:positive])}.mp3")

    File.write!(sample_path, "FAKE-AUDIO")

    on_exit(fn -> File.rm(sample_path) end)

    assert {:ok, %{voice_id: "voice_clone_123", name: "Minha Voz"}} =
             Audio.clone_voice(%{"name" => "Minha Voz"}, [
               %{path: sample_path, filename: "sample.mp3", content_type: "audio/mpeg"}
             ])

    assert_received {:clone_instant_voice, "Minha Voz",
                     [%{path: ^sample_path, filename: "sample.mp3"}]}
  end

  test "clone_voice requires a name and at least one sample" do
    assert {:error, changeset} = Audio.clone_voice(%{"name" => ""}, [])

    assert %{
             name: ["can't be blank"],
             files: ["selecione pelo menos um arquivo de audio"]
           } = errors_on(changeset)
  end
end
