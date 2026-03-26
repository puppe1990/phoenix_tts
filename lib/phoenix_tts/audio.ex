defmodule PhoenixTts.Audio do
  import Ecto.Query, warn: false

  alias PhoenixTts.Audio.Generation
  alias PhoenixTts.Audio.Voice
  alias PhoenixTts.ElevenLabs.EndpointCatalog
  alias PhoenixTts.Repo

  def list_generations do
    from(g in Generation, order_by: [desc: g.inserted_at, desc: g.id])
    |> Repo.all()
  end

  def change_clone_voice(attrs \\ %{}, sample_count \\ 0) do
    {%{}, %{name: :string}}
    |> Ecto.Changeset.cast(attrs, [:name])
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_length(:name, max: 100)
    |> validate_sample_count(sample_count)
  end

  def change_generation(attrs \\ %{}) do
    defaults = %{
      "text" => "",
      "voice_id" => "",
      "model_id" => "",
      "output_format" => default_output_format(),
      "language_code" => "pt"
    }

    %Generation{}
    |> Generation.form_changeset(Map.merge(defaults, attrs))
  end

  def list_voices do
    from(v in Voice, order_by: [asc: v.name, asc: v.voice_id])
    |> Repo.all()
    |> Enum.map(&serialize_voice/1)
  end

  def create_generation(attrs) do
    changeset = Generation.form_changeset(%Generation{}, attrs)

    if changeset.valid? do
      params = Ecto.Changeset.apply_changes(changeset)

      with {:ok, response} <-
             elevenlabs_client().synthesize_speech(params.text,
               voice_id: params.voice_id,
               model_id: params.model_id,
               output_format: params.output_format,
               language_code: blank_to_nil(params.language_code),
               voice_settings: %{stability: 0.45, similarity_boost: 0.8}
             ),
           {:ok, audio_path} <- persist_audio(response.audio),
           {:ok, generation} <-
             insert_generation(
               Map.merge(params, %{
                 character_count: response.character_count,
                 request_id: response.request_id,
                 remote_history_item_id: response.history_item_id
               }),
               audio_path,
               response.content_type
             ) do
        {:ok, generation}
      else
        {:error, %Ecto.Changeset{} = error_changeset} ->
          {:error, error_changeset}

        {:error, reason} ->
          {:error, add_runtime_error(changeset, reason)}
      end
    else
      {:error, changeset}
    end
  end

  def clone_voice(attrs, files) do
    changeset = change_clone_voice(attrs, length(files))

    if changeset.valid? do
      name = Ecto.Changeset.get_field(changeset, :name)

      case elevenlabs_client().clone_instant_voice(name, files) do
        {:ok, clone} ->
          maybe_persist_cloned_voice(clone)
          {:ok, clone}

        {:error, reason} ->
          {:error, Ecto.Changeset.add_error(changeset, :name, normalize_error(reason))}
      end
    else
      {:error, changeset}
    end
  end

  def available_voices do
    case sync_voices() do
      {:ok, voices} -> voices
      {:error, _reason} -> list_voices()
    end
  end

  def sync_voices do
    with {:ok, %{voices: voices}} <- elevenlabs_client().list_voices(%{page_size: 25}),
         {count, _} when count >= 0 <- upsert_voices(voices) do
      {:ok, list_voices()}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def available_models do
    case elevenlabs_client().list_models() do
      {:ok, models} ->
        Enum.filter(models, & &1.can_do_text_to_speech)

      {:error, _reason} ->
        []
    end
  end

  def remote_history(params \\ %{}) do
    case remote_history_page(params) do
      {:ok, %{items: items}} -> items
      {:error, _reason} -> []
    end
  end

  def remote_history_page(params \\ %{}) do
    params = Map.merge(%{page_size: 10}, params)

    case elevenlabs_client().list_history(params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_history_audio(history_item_id) do
    elevenlabs_client().get_history_audio(history_item_id)
  end

  def subscription_overview do
    case elevenlabs_client().get_subscription() do
      {:ok, subscription} ->
        used = subscription.character_count || 0
        limit = subscription.character_limit || 0

        {:ok,
         %{
           tier: subscription.tier,
           status: subscription.status,
           used_tokens: used,
           total_tokens: limit,
           remaining_tokens: max(limit - used, 0),
           next_reset_unix: subscription.next_character_count_reset_unix
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def endpoint_catalog, do: EndpointCatalog.list()

  def storage_dir do
    Application.fetch_env!(:phoenix_tts, :audio_storage_dir)
  end

  def api_key_configured? do
    Application.get_env(:phoenix_tts, :elevenlabs_api_key) not in [nil, ""]
  end

  def default_output_format do
    Application.get_env(:phoenix_tts, :elevenlabs_default_output_format, "mp3_44100_128")
  end

  defp insert_generation(params, audio_path, content_type) do
    %Generation{}
    |> Generation.persistence_changeset(%{
      text: params.text,
      voice_id: params.voice_id,
      model_id: params.model_id,
      output_format: params.output_format,
      language_code: blank_to_nil(params.language_code),
      audio_path: audio_path,
      character_count: params.character_count || String.length(params.text),
      content_type: content_type,
      request_id: params.request_id,
      remote_history_item_id: params.remote_history_item_id
    })
    |> Repo.insert()
  end

  defp persist_audio(binary) do
    relative_path = Path.join("generated", "#{Ecto.UUID.generate()}.mp3")
    absolute_path = Path.join(storage_dir(), relative_path)

    absolute_path
    |> Path.dirname()
    |> File.mkdir_p()

    case File.write(absolute_path, binary, [:binary]) do
      :ok -> {:ok, relative_path}
      {:error, reason} -> {:error, "Nao foi possivel salvar o mp3: #{inspect(reason)}"}
    end
  end

  defp add_runtime_error(changeset, reason) do
    Ecto.Changeset.add_error(changeset, :text, normalize_error(reason))
  end

  defp validate_sample_count(changeset, sample_count) when sample_count > 0, do: changeset

  defp validate_sample_count(changeset, _sample_count) do
    Ecto.Changeset.add_error(changeset, :files, "selecione pelo menos um arquivo de audio")
  end

  defp normalize_error(message) when is_binary(message), do: message
  defp normalize_error(other), do: "Erro ao gerar audio: #{inspect(other)}"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp elevenlabs_client do
    Application.fetch_env!(:phoenix_tts, :elevenlabs_client)
  end

  defp upsert_voices([]), do: {0, nil}

  defp upsert_voices(voices) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(voices, fn voice ->
        %{
          voice_id: voice.id,
          name: voice.name,
          category: Map.get(voice, :category),
          labels: Map.get(voice, :labels, %{}),
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(
      Voice,
      entries,
      on_conflict: {:replace, [:name, :category, :labels, :updated_at]},
      conflict_target: [:voice_id]
    )
  end

  defp serialize_voice(%Voice{} = voice) do
    %{
      id: voice.voice_id,
      name: voice.name,
      category: voice.category,
      labels: voice.labels || %{}
    }
  end

  defp maybe_persist_cloned_voice(%{voice_id: voice_id, name: name} = clone)
       when is_binary(voice_id) and voice_id != "" and is_binary(name) and name != "" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      Voice,
      [
        %{
          voice_id: voice_id,
          name: name,
          category: Map.get(clone, :category, "cloned"),
          labels: Map.get(clone, :labels, %{}),
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:name, :category, :labels, :updated_at]},
      conflict_target: [:voice_id]
    )
  end

  defp maybe_persist_cloned_voice(_clone), do: :ok
end
