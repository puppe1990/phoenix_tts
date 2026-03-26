defmodule PhoenixTts.AudioTest do
  use PhoenixTts.DataCase, async: false

  alias PhoenixTts.Audio
  alias PhoenixTts.Audio.Generation
  alias PhoenixTts.Audio.Voice

  defmodule FakeElevenLabsClient do
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

    def list_history(_params \\ %{}) do
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
         has_more: false,
         last_history_item_id: "hist_remote_1"
       }}
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

  test "catalog helpers expose remote voices, models, history and endpoint map" do
    assert [%{id: "voice_br", category: "premade"}] = Audio.available_voices()
    assert [%{id: "voice_br", category: "premade"}] = Audio.list_voices()
    assert [%Voice{voice_id: "voice_br", category: "premade"}] = Repo.all(Voice)
    assert [%{id: "eleven_multilingual_v2"}] = Audio.available_models()
    assert [%{history_item_id: "hist_remote_1"}] = Audio.remote_history()

    endpoint_slugs =
      Audio.endpoint_catalog()
      |> Enum.map(& &1.slug)

    assert "text-to-speech-convert" in endpoint_slugs
    assert "voices-search" in endpoint_slugs
    assert "models-list" in endpoint_slugs
    assert "history-list" in endpoint_slugs
  end
end
