import Config

config :dummy,
  ecto_repos: [Dummy.Repo],
  generators: [timestamp_type: :utc_datetime]

config :dummy, DummyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DummyWeb.ErrorHTML, json: DummyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Dummy.PubSub,
  live_view: [signing_salt: "dummy_live_view"]

config :phoenix, :json_library, Jason

config :wax_,
  origin: "http://localhost:4000",
  rp_id: :auto

config :phoenix_lens,
  repo: Dummy.Repo,
  masked_fields: [:email, :first_name, :phone, :ip, :author_email]

import_config "#{config_env()}.exs"
