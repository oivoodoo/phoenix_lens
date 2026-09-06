defmodule PhoenixLens.Standalone.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :phoenix_lens

  @session_options [
    store: :cookie,
    key: "_phoenix_lens_key",
    signing_salt: "phoenix_lens",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug PhoenixLens.Standalone.Router
end
