defmodule PhoenixTts.Repo.Migrations.AddElevenlabsMetadataToAudioGenerations do
  use Ecto.Migration

  def change do
    alter table(:audio_generations) do
      add :output_format, :string, null: false, default: "mp3_44100_128"
      add :language_code, :string
      add :request_id, :string
      add :remote_history_item_id, :string
    end

    create unique_index(:audio_generations, [:request_id])
  end
end
