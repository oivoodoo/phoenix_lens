import Config

config :phoenix, :plug_init_mode, :runtime
config :logger, level: :warning

config :phoenix_lens, PhoenixLens.TestEndpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("t", 64),
  live_view: [signing_salt: "lens_test_lv"],
  server: false,
  pubsub_server: PhoenixLens.TestPubSub

if url = System.get_env("DATABASE_URL") do
  config :phoenix_lens, PhoenixLens.TestRepo,
    url: url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5
end
