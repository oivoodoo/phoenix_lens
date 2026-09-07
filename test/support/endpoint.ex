defmodule PhoenixLens.TestRouter do
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

  scope "/" do
    pipe_through :browser
    lens("/lens")
  end

  scope "/dev" do
    scope "/internal" do
      pipe_through :browser
      lens("/lens")
    end
  end
end

defmodule PhoenixLens.TestEndpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_lens

  @session_options [
    store: :cookie,
    key: "_phoenix_lens_test",
    signing_salt: "lenstest"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:uri, session: @session_options]],
    longpoll: [connect_info: [:uri, session: @session_options]]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug PhoenixLensWeb.Plugs.MCP, path: "/lens/mcp"

  plug Plug.Session, @session_options
  plug PhoenixLens.TestRouter
end
