defmodule PhoenixLens.Standalone.Router do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import PhoenixLensWeb.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :lens_gate do
    plug PhoenixLensWeb.Plugs.Dashboard, mount_path: "/lens", skip_operator: true
  end

  get "/health", PhoenixLens.Standalone.HealthController, :index

  scope "/lens" do
    pipe_through [:browser, :lens_gate]

    live_session :phoenix_lens_gate,
      on_mount: PhoenixLensWeb.Hooks,
      session: {PhoenixLensWeb.Plugs.Dashboard, :session, []},
      root_layout: {PhoenixLensWeb.Layouts, :root} do
      live "/setup", PhoenixLensWeb.SetupLive, :index
      live "/login", PhoenixLensWeb.LoginLive, :index
    end

    get "/session/complete", PhoenixLens.Standalone.SessionController, :complete
    post "/logout", PhoenixLens.Standalone.SessionController, :delete
    get "/logout", PhoenixLens.Standalone.SessionController, :delete
  end

  scope "/" do
    pipe_through :browser
    lens("/lens")
  end

  get "/", PhoenixLens.Standalone.RedirectController, :index
end
