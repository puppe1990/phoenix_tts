defmodule PhoenixTts.Audio.Voice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_voices" do
    field :voice_id, :string
    field :name, :string
    field :category, :string
    field :labels, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(voice, attrs) do
    voice
    |> cast(attrs, [:voice_id, :name, :category, :labels])
    |> validate_required([:voice_id, :name])
    |> validate_length(:voice_id, min: 2)
    |> unique_constraint(:voice_id)
  end
end
