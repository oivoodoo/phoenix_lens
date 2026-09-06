import Config

if url = System.get_env("DATABASE_URL") do
  config :dummy, Dummy.Repo,
    url: url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end

if port = System.get_env("PORT") do
  config :dummy, DummyWeb.Endpoint, http: [ip: {0, 0, 0, 0}, port: String.to_integer(port)]
end
