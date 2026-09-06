import Config

config :dummy, Dummy.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5556,
  database: "dummy_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :dummy, DummyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("t", 64),
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
