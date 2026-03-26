defmodule PhoenixTts.Repo.Migrations.CreateAudioGenerations do
  use Ecto.Migration

  def change do
    create table(:audio_generations) do
      add :text, :text, null: false
      add :voice_id, :string, null: false
      add :model_id, :string, null: false
      add :audio_path, :string, null: false
      add :character_count, :integer, null: false
      add :content_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:audio_generations, [:inserted_at])
  end
end
