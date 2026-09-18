defmodule PhoenixLens.StandaloneTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.Standalone

  @env_keys ~w(
    DATABASE_URL PHOENIX_LENS_DATABASE_URL
    POSTGRES_HOST POSTGRES_PORT POSTGRES_USER POSTGRES_USERNAME
    POSTGRES_PASSWORD POSTGRES_DB POSTGRES_DATABASE PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE
    PORT PHX_HOST PHX_SCHEME SECRET_KEY_BASE
    PHOENIX_LENS_USERNAME PHOENIX_LENS_PASSWORD
    HTTP_BASIC_USERNAME HTTP_BASIC_PASSWORD
    BASIC_AUTH_USERNAME BASIC_AUTH_PASSWORD
    SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_USER SMTP_PASSWORD SMTP_FROM SMTP_TLS
  )

  setup do
    previous_env = Map.new(@env_keys, &{&1, System.get_env(&1)})
    previous_app = Application.get_all_env(:phoenix_lens)

    Enum.each(@env_keys, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous_env, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      for {key, _} <- Application.get_all_env(:phoenix_lens),
          do: Application.delete_env(:phoenix_lens, key)

      for {key, value} <- previous_app, do: Application.put_env(:phoenix_lens, key, value)
    end)

    :ok
  end

  test "database_url prefers DATABASE_URL" do
    System.put_env("DATABASE_URL", "postgres://a:b@db:5432/app")
    System.put_env("POSTGRES_HOST", "ignored")
    assert Standalone.database_url() == "postgres://a:b@db:5432/app"
  end

  test "database_url builds from POSTGRES_* parts" do
    System.put_env("POSTGRES_HOST", "db.internal")
    System.put_env("POSTGRES_PORT", "6543")
    System.put_env("POSTGRES_USER", "lens")
    System.put_env("POSTGRES_PASSWORD", "s3cret")
    System.put_env("POSTGRES_DB", "lens_prod")

    assert Standalone.database_url() == "postgres://lens:s3cret@db.internal:6543/lens_prod"
  end

  test "database_url percent-encodes special characters in the password" do
    System.put_env("POSTGRES_HOST", "localhost")
    System.put_env("POSTGRES_USER", "lens")
    System.put_env("POSTGRES_PASSWORD", "p@ss:word/1")
    System.put_env("POSTGRES_DB", "lens")

    assert Standalone.database_url() == "postgres://lens:p%40ss%3Aword%2F1@localhost:5432/lens"
  end

  test "database_url is nil without DATABASE_URL or POSTGRES_HOST" do
    assert Standalone.database_url() == nil
  end

  test "smtp_from_env requires host and from" do
    assert Standalone.smtp_from_env() == nil

    System.put_env("SMTP_HOST", "smtp.example.com")
    System.put_env("SMTP_FROM", "lens@example.com")
    System.put_env("SMTP_PORT", "2525")
    System.put_env("SMTP_USERNAME", "mailer")
    System.put_env("SMTP_PASSWORD", "secret")
    System.put_env("SMTP_TLS", "true")

    smtp = Standalone.smtp_from_env()
    assert smtp[:host] == "smtp.example.com"
    assert smtp[:from] == "lens@example.com"
    assert smtp[:port] == 2525
    assert smtp[:username] == "mailer"
    assert smtp[:password] == "secret"
    assert smtp[:tls] == true
  end

  test "configure! reads PORT, HTTP basic, SMTP, and postgres settings" do
    System.put_env("PORT", "9090")
    System.put_env("PHX_HOST", "lens.example.com")
    System.put_env("POSTGRES_HOST", "postgres")
    System.put_env("POSTGRES_USER", "lens")
    System.put_env("POSTGRES_PASSWORD", "lens")
    System.put_env("POSTGRES_DB", "lens")
    System.put_env("HTTP_BASIC_USERNAME", "gate")
    System.put_env("HTTP_BASIC_PASSWORD", "keep-out")
    System.put_env("SMTP_HOST", "smtp.example.com")
    System.put_env("SMTP_FROM", "lens@example.com")
    System.put_env("SECRET_KEY_BASE", String.duplicate("s", 64))

    assert :ok = Standalone.configure!()

    assert Application.get_env(:phoenix_lens, :standalone) == true
    assert Application.get_env(:phoenix_lens, :repo) == PhoenixLens.Standalone.Repo
    assert Application.get_env(:phoenix_lens, :username) == "gate"
    assert Application.get_env(:phoenix_lens, :password) == "keep-out"

    smtp = Application.get_env(:phoenix_lens, :smtp)
    assert smtp[:host] == "smtp.example.com"

    endpoint = Application.get_env(:phoenix_lens, PhoenixLens.Standalone.Endpoint)
    assert endpoint[:http][:port] == 9090
    assert endpoint[:url][:host] == "lens.example.com"
    assert endpoint[:server] == true
  end
end
