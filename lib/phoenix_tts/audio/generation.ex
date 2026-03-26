defmodule PhoenixTts.Audio.Generation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_generations" do
    field :audio_path, :string
    field :character_count, :integer
    field :content_type, :string
    field :language_code, :string
    field :model_id, :string
    field :output_format, :string
    field :remote_history_item_id, :string
    field :request_id, :string
    field :text, :string
    field :voice_id, :string

    timestamps(type: :utc_datetime)
  end

  def form_changeset(generation, attrs) do
    generation
    |> cast(attrs, [:text, :voice_id, :model_id, :output_format, :language_code])
    |> validate_required([:text, :voice_id, :model_id, :output_format])
    |> validate_length(:text, min: 10, max: 5_000)
    |> validate_length(:voice_id, min: 2)
    |> validate_length(:model_id, min: 2)
    |> validate_length(:output_format, min: 3)
  end

  def persistence_changeset(generation, attrs) do
    generation
    |> cast(attrs, [
      :text,
      :voice_id,
      :model_id,
      :output_format,
      :language_code,
      :audio_path,
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
      :audio_path,
      :character_count,
      :content_type
    ])
  end
end
