defmodule PhoenixLens.Standalone do
  @moduledoc false

  def enabled? do
    Application.get_env(:phoenix_lens, :standalone, false) == true or
      System.get_env("PHOENIX_LENS_SERVER") in ["1", "true"]
  end

  def children do
    if enabled?() do
      [
        PhoenixLens.Standalone.Repo,
        {Phoenix.PubSub, name: PhoenixLens.PubSub},
        PhoenixLens.Standalone.Endpoint
      ]
    else
      []
    end
  end

  def migrate! do
    PhoenixLens.Migrations.ensure_all(PhoenixLens.Standalone.Repo)
  end

  def configure!(opts \\ []) do
    port = Keyword.get(opts, :port) || env_int("PORT", 8080)
    secret = secret_key_base()
    url = database_url()
    host = System.get_env("PHX_HOST") || "localhost"
    scheme = System.get_env("PHX_SCHEME") || "http"
    url_port = url_port(scheme, port)

    Application.put_env(:phoenix_lens, :standalone, true)

    if is_binary(url) and url != "" do
      Application.put_env(:phoenix_lens, :url, url)
      Application.put_env(:phoenix_lens, :repo, PhoenixLens.Standalone.Repo)

      Application.put_env(
        :phoenix_lens,
        PhoenixLens.Standalone.Repo,
        repo_config(url)
      )
    end

    if smtp = smtp_from_env() do
      Application.put_env(:phoenix_lens, :smtp, smtp)
    end

    if username = first_env(~w(PHOENIX_LENS_USERNAME HTTP_BASIC_USERNAME BASIC_AUTH_USERNAME)) do
      Application.put_env(:phoenix_lens, :username, username)
    end

    if password = first_env(~w(PHOENIX_LENS_PASSWORD HTTP_BASIC_PASSWORD BASIC_AUTH_PASSWORD)) do
      Application.put_env(:phoenix_lens, :password, password)
    end

    origin = public_origin(scheme, host, url_port)
    Application.put_env(:wax_, :origin, origin)

    endpoint = Application.get_env(:phoenix_lens, PhoenixLens.Standalone.Endpoint, [])

    Application.put_env(
      :phoenix_lens,
      PhoenixLens.Standalone.Endpoint,
      Keyword.merge(endpoint,
        http: [ip: {0, 0, 0, 0}, port: port],
        secret_key_base: secret,
        server: true,
        url: [host: host, port: url_port, scheme: scheme],
        check_origin: check_origin(scheme, host, url_port)
      )
    )

    :ok
  end

  def database_url do
    first_env(~w(DATABASE_URL PHOENIX_LENS_DATABASE_URL)) || build_postgres_url()
  end

  def smtp_from_env do
    host = first_env(~w(SMTP_HOST SMTP_RELAY))
    from = System.get_env("SMTP_FROM")

    if present?(host) and present?(from) do
      [
        host: host,
        from: from,
        port: env_int("SMTP_PORT", 587),
        username: first_env(~w(SMTP_USERNAME SMTP_USER)) || "",
        password: System.get_env("SMTP_PASSWORD") || "",
        tls: env_bool("SMTP_TLS", true)
      ]
    end
  end

  defp build_postgres_url do
    host = first_env(~w(POSTGRES_HOST PGHOST))

    if present?(host) do
      user = first_env(~w(POSTGRES_USER POSTGRES_USERNAME PGUSER)) || "postgres"
      password = first_env(~w(POSTGRES_PASSWORD PGPASSWORD)) || ""
      database = first_env(~w(POSTGRES_DB POSTGRES_DATABASE PGDATABASE)) || "postgres"
      port = env_int("POSTGRES_PORT", env_int("PGPORT", 5432))
      userinfo = URI.encode_www_form(user) <> ":" <> URI.encode_www_form(password)
      "postgres://#{userinfo}@#{host}:#{port}/#{URI.encode_www_form(database)}"
    end
  end

  defp repo_config(url) do
    [
      url: url,
      pool_size: env_int("POOL_SIZE", 5),
      timeout: 30_000
    ]
    |> maybe_ssl(url)
  end

  defp maybe_ssl(opts, url) do
    uri = URI.parse(url)
    params = URI.decode_query(uri.query || "")

    ssl? =
      env_bool("POSTGRES_SSL", false) or
        params["sslmode"] in ["require", "verify-full", "verify-ca"]

    if ssl? do
      Keyword.put(opts, :ssl, verify: :verify_none)
    else
      opts
    end
  end

  defp url_port("https", _listen_port), do: env_int("PHX_URL_PORT", 443)
  defp url_port(_scheme, listen_port), do: env_int("PHX_URL_PORT", listen_port)

  defp public_origin(scheme, host, port) do
    default = if scheme == "https", do: 443, else: 80

    if port == default do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end

  defp check_origin(scheme, host, port) do
    [
      "#{scheme}://#{host}",
      "#{scheme}://#{host}:#{port}",
      "http://localhost",
      "http://localhost:#{port}",
      "http://127.0.0.1",
      "http://127.0.0.1:#{port}"
    ]
    |> Enum.uniq()
  end

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      value -> String.to_integer(value)
    end
  end

  defp env_bool(name, default) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      value -> String.downcase(value) in ["1", "true", "yes", "on"]
    end
  end

  defp first_env(keys) do
    Enum.find_value(keys, fn key ->
      case System.get_env(key) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp secret_key_base do
    case System.get_env("SECRET_KEY_BASE") do
      value when is_binary(value) and byte_size(value) >= 64 -> value
      _ -> random_secret()
    end
  end

  defp random_secret do
    48 |> :crypto.strong_rand_bytes() |> Base.encode64()
  end
end
