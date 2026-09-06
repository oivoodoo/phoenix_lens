defmodule DummyWeb.Router do
  use DummyWeb, :router
  import PhoenixLensWeb.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DummyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", DummyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/" do
    pipe_through :browser
    lens("/lens")
  end
end
