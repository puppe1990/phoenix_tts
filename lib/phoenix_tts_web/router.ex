defmodule PhoenixTtsWeb.Router do
  use PhoenixTtsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhoenixTtsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug PhoenixTtsWeb.Plugs.ApiCors
    plug PhoenixTtsWeb.Plugs.ApiAuth
  end

  scope "/", PhoenixTtsWeb do
    pipe_through :browser

    get "/openapi.yaml", PageController, :openapi
    get "/api-docs", PageController, :api_docs
    get "/api-docs.md", PageController, :api_markdown
    get "/history/:history_item_id/audio", HistoryAudioController, :show
    get "/generations/:id/audio", GenerationAudioController, :show
    live "/", AudioLive, :index
    live "/clone", AudioLive, :clone
    live "/recentes", AudioLive, :recentes
    live "/config", AudioLive, :config
  end

  scope "/api", PhoenixTtsWeb do
    pipe_through :api

    options "/*path", AudioApiController, :options
    get "/voices", AudioApiController, :voices
    get "/models", AudioApiController, :models
    get "/subscription", AudioApiController, :subscription
    get "/history", AudioApiController, :history
    get "/history/:history_item_id/audio", AudioApiController, :history_audio
    get "/generations", AudioApiController, :index
    get "/generations/:id", AudioApiController, :show
    get "/generations/:id/audio", AudioApiController, :generation_audio
    post "/generations", AudioApiController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:phoenix_tts, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PhoenixTtsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
