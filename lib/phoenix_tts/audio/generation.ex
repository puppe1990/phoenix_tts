defmodule PhoenixTts.Audio.Generation do
  use Ecto.Schema
  import Ecto.Changeset

  @quality_presets ~w(high balanced consistent)

  schema "audio_generations" do
    field :audio_path, :string
    field :audio_binary, :binary
    field :character_count, :integer
    field :content_type, :string
    field :language_code, :string
    field :model_id, :string
    field :output_format, :string
    field :quality_preset, :string
    field :remote_history_item_id, :string
    field :request_id, :string
    field :similarity_boost, :float
    field :speaker_boost, :boolean
    field :stability, :float
    field :style, :float
    field :text, :string
    field :voice_id, :string

    timestamps(type: :utc_datetime)
  end

  def quality_presets, do: @quality_presets

  def form_changeset(generation, attrs) do
    generation
    |> cast(attrs, [
      :text,
      :voice_id,
      :model_id,
      :output_format,
      :language_code,
      :quality_preset,
      :stability,
      :similarity_boost,
      :style,
      :speaker_boost
    ])
    |> validate_required([:text, :voice_id, :model_id, :output_format])
    |> validate_length(:text, min: 10, max: 10_000)
    |> validate_length(:voice_id, min: 2)
    |> validate_length(:model_id, min: 2)
    |> validate_length(:output_format, min: 3)
    |> validate_inclusion(:quality_preset, @quality_presets)
    |> validate_number(:stability, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(
      :similarity_boost,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> validate_number(:style, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  def persistence_changeset(generation, attrs) do
    generation
    |> cast(attrs, [
      :text,
      :voice_id,
      :model_id,
      :output_format,
      :language_code,
      :quality_preset,
      :stability,
      :similarity_boost,
      :style,
      :speaker_boost,
      :audio_path,
      :audio_binary,
      :character_count,
      :content_type,
      :request_id,
      :remote_history_item_id
    ])
    |> validate_required([
      :text,
      :voice_id,
      :model_id,
      :output_format,
      :character_count,
      :content_type
    ])
    |> validate_inclusion(:quality_preset, @quality_presets)
    |> validate_number(:stability, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(
      :similarity_boost,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> validate_number(:style, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> ensure_embedded_audio_path()
    |> validate_audio_source_present()
  end

  defp ensure_embedded_audio_path(changeset) do
    audio_path = get_field(changeset, :audio_path)
    audio_binary = get_field(changeset, :audio_binary)

    if is_binary(audio_binary) and !is_binary(audio_path) do
      put_change(changeset, :audio_path, "embedded://#{Ecto.UUID.generate()}.mp3")
    else
      changeset
    end
  end

  defp validate_audio_source_present(changeset) do
    audio_path = get_field(changeset, :audio_path)
    audio_binary = get_field(changeset, :audio_binary)

    if is_binary(audio_binary) or (is_binary(audio_path) and audio_path != "") do
      changeset
    else
      add_error(changeset, :audio_binary, "audio gerado nao foi persistido")
    end
  end
end
