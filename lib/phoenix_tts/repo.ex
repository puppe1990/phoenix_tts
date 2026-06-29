defmodule PhoenixTts.Repo do
  use Ecto.Repo,
    otp_app: :phoenix_tts,
    adapter: Ecto.Adapters.LibSql
end
