defmodule PhoenixTts.Repo do
  use Ecto.Repo,
    otp_app: :phoenix_tts,
    adapter:
      Application.compile_env(:phoenix_tts, [PhoenixTts.Repo, :adapter], Ecto.Adapters.SQLite3)
end
