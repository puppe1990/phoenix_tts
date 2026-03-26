defmodule PhoenixTts.Repo.Migrations.StoreAudioBinaryInGenerations do
  use Ecto.Migration

  def change do
    alter table(:audio_generations) do
      add :audio_binary, :binary
    end
  end
end
