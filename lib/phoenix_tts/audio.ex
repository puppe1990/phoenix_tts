defmodule PhoenixTts.Audio do
  import Ecto.Query, warn: false

  alias PhoenixTts.Audio.Generation
  alias PhoenixTts.Audio.Voice
  alias PhoenixTts.ElevenLabs.EndpointCatalog
  alias PhoenixTts.Repo

  @practical_chunk_size 5_000
  @max_split_chunks 2

  def list_generations do
    from(g in Generation, order_by: [desc: g.inserted_at, desc: g.id])
    |> Repo.all()
  end

  def get_generation(id), do: Repo.get(Generation, id)

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

      request_opts = [
        voice_id: params.voice_id,
        model_id: params.model_id,
        output_format: params.output_format,
        language_code: blank_to_nil(params.language_code),
        voice_settings: %{stability: 0.45, similarity_boost: 0.8}
      ]

      with {:ok, responses} <- synthesize_text(params.text, request_opts),
           audio_binary = merge_audio_chunks(responses),
           {:ok, generation} <-
             insert_generation(
               Map.merge(params, %{
                 character_count: aggregate_character_count(responses, params.text),
                 request_id: aggregate_header_value(responses, :request_id),
                 remote_history_item_id: aggregate_header_value(responses, :history_item_id)
               }),
               audio_binary,
               content_type_for(responses)
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
          {:error, Ecto.Changeset.add_error(changeset, :runtime, normalize_error(reason))}
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
           used_credits: used,
           total_credits: limit,
           remaining_credits: max(limit - used, 0),
           next_reset_unix: subscription.next_character_count_reset_unix
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def endpoint_catalog, do: EndpointCatalog.list()

  def api_key_configured? do
    Application.get_env(:phoenix_tts, :elevenlabs_api_key) not in [nil, ""]
  end

  def storage_dir do
    Application.fetch_env!(:phoenix_tts, :audio_storage_dir)
  end

  def default_output_format do
    Application.get_env(:phoenix_tts, :elevenlabs_default_output_format, "mp3_44100_128")
  end

  defp synthesize_text(text, request_opts) do
    with {:ok, chunks} <- split_text_for_generation(text) do
      Enum.reduce_while(chunks, {:ok, []}, fn chunk, {:ok, responses} ->
        case elevenlabs_client().synthesize_speech(chunk, request_opts) do
          {:ok, response} -> {:cont, {:ok, responses ++ [response]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp split_text_for_generation(text) do
    character_count = String.length(text)

    cond do
      character_count <= @practical_chunk_size ->
        {:ok, [text]}

      character_count <= @practical_chunk_size * @max_split_chunks ->
        {:ok, split_text_in_two(text)}

      true ->
        {:error, "Texto acima do limite operacional. Reduza para até 10.000 caracteres."}
    end
  end

  defp split_text_in_two(text) do
    total = String.length(text)
    min_split = max(total - @practical_chunk_size, 1)
    max_split = min(@practical_chunk_size, total - 1)
    split_index = find_split_index(text, min_split, max_split)

    [
      text |> String.slice(0, split_index) |> String.trim(),
      text |> String.slice(split_index, total - split_index) |> String.trim()
    ]
    |> Enum.reject(&(&1 == ""))
  end

  defp find_split_index(text, min_split, max_split) do
    separators = ["\n\n", "\n", ". ", "! ", "? ", "; ", ": ", ", ", " "]

    Enum.find_value(separators, fn separator ->
      Enum.find_value(Range.new(max_split, min_split, -1), fn index ->
        separator_length = String.length(separator)

        if String.slice(text, max(index - separator_length, 0), separator_length) == separator do
          index
        end
      end)
    end) || max_split
  end

  defp merge_audio_chunks(responses) do
    responses
    |> Enum.map(& &1.audio)
    |> IO.iodata_to_binary()
  end

  defp aggregate_character_count(responses, original_text) do
    counts =
      responses
      |> Enum.map(& &1.character_count)
      |> Enum.reject(&is_nil/1)

    if counts == [], do: String.length(original_text), else: Enum.sum(counts)
  end

  defp aggregate_header_value(responses, key) do
    responses
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
    |> blank_to_nil()
  end

  defp content_type_for([first | _]), do: first.content_type || "audio/mpeg"
  defp content_type_for([]), do: "audio/mpeg"

  defp insert_generation(params, audio_binary, content_type) do
    %Generation{}
    |> Generation.persistence_changeset(%{
      text: params.text,
      voice_id: params.voice_id,
      model_id: params.model_id,
      output_format: params.output_format,
      language_code: blank_to_nil(params.language_code),
      audio_binary: audio_binary,
      character_count: params.character_count || String.length(params.text),
      content_type: content_type,
      request_id: params.request_id,
      remote_history_item_id: params.remote_history_item_id
    })
    |> Repo.insert()
  end

  defp add_runtime_error(changeset, reason) do
    Ecto.Changeset.add_error(changeset, :runtime, normalize_error(reason))
  end

  defp validate_sample_count(changeset, sample_count) when sample_count > 0, do: changeset

  defp validate_sample_count(changeset, _sample_count) do
    Ecto.Changeset.add_error(changeset, :files, "selecione pelo menos um arquivo de audio")
  end

  defp normalize_error("timeout") do
    "A ElevenLabs demorou mais que o limite local. O áudio pode ter sido gerado; confira Itens recentes."
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
