import Config

config :dummy, Dummy.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5556,
  database: "dummy_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :dummy, DummyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: String.duplicate("d", 64),
  watchers: []

config :dummy, DummyWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"lib/dummy_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
