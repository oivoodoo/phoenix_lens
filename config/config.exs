import Config

config :phoenix, :json_library, Jason

config :wax_,
  origin: "http://localhost:4000",
  rp_id: :auto

config :phoenix_lens, :standalone, false

config :phoenix_lens, PhoenixLens.Standalone.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PhoenixLens.Standalone.ErrorHTML],
    layout: false
  ],
  pubsub_server: PhoenixLens.PubSub,
  live_view: [signing_salt: "phoenix_lens_lv"],
  server: false

import_config "#{config_env()}.exs"
