defmodule PhoenixTts.Repo.Migrations.AddQualityControlsToAudioGenerations do
  use Ecto.Migration

  def change do
    alter table(:audio_generations) do
      add :quality_preset, :string
      add :stability, :float
      add :similarity_boost, :float
      add :style, :float
      add :speaker_boost, :boolean
    end
  end
end
