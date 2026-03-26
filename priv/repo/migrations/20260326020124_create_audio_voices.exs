defmodule PhoenixTts.Repo.Migrations.CreateAudioVoices do
  use Ecto.Migration

  def change do
    create table(:audio_voices) do
      add :voice_id, :string, null: false
      add :name, :string, null: false
      add :category, :string
      add :labels, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:audio_voices, [:voice_id])
    create index(:audio_voices, [:name])
  end
end
