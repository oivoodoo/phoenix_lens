defmodule PhoenixLens.ConfigTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.Config

  setup do
    previous = Application.get_all_env(:phoenix_lens)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_lens),
          do: Application.delete_env(:phoenix_lens, key)

      for {key, value} <- previous, do: Application.put_env(:phoenix_lens, key, value)
    end)

    :ok
  end

  test "repo: becomes a primary database" do
    Application.delete_env(:phoenix_lens, :databases)
    Application.put_env(:phoenix_lens, :repo, Foo.Repo)
    cfg = Config.get()
    assert cfg.databases["primary"][:repo] == Foo.Repo
    assert cfg.metadata_repo == Foo.Repo
  end

  test "databases: list is normalized" do
    Application.delete_env(:phoenix_lens, :repo)

    Application.put_env(:phoenix_lens, :databases,
      primary: [repo: Foo.Repo],
      analytics: [url: "postgres://localhost/a", name: "Analytics"]
    )

    cfg = Config.get()
    assert cfg.databases["primary"][:repo] == Foo.Repo
    assert cfg.databases["analytics"][:name] == "Analytics"
  end

  test "postgres_dsn from a URL database" do
    dsn =
      Config.postgres_dsn(
        id: "primary",
        url: "postgres://alice:s3cret@db.internal:5556/app"
      )

    assert dsn == "postgresql://alice:s3cret@db.internal:5556/app"
  end

  test "timeout and max_rows defaults" do
    Application.delete_env(:phoenix_lens, :timeout_ms)
    Application.delete_env(:phoenix_lens, :max_rows)
    cfg = Config.get()
    assert cfg.timeout_ms == 5_000
    assert cfg.max_rows == 10_000
  end

  test "HTTP basic falls back to HTTP_BASIC_* and BASIC_AUTH_* env vars" do
    Application.delete_env(:phoenix_lens, :username)
    Application.delete_env(:phoenix_lens, :password)

    previous = %{
      "PHOENIX_LENS_USERNAME" => System.get_env("PHOENIX_LENS_USERNAME"),
      "PHOENIX_LENS_PASSWORD" => System.get_env("PHOENIX_LENS_PASSWORD"),
      "HTTP_BASIC_USERNAME" => System.get_env("HTTP_BASIC_USERNAME"),
      "HTTP_BASIC_PASSWORD" => System.get_env("HTTP_BASIC_PASSWORD"),
      "BASIC_AUTH_USERNAME" => System.get_env("BASIC_AUTH_USERNAME"),
      "BASIC_AUTH_PASSWORD" => System.get_env("BASIC_AUTH_PASSWORD")
    }

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    Enum.each(Map.keys(previous), &System.delete_env/1)

    System.put_env("HTTP_BASIC_USERNAME", "gate")
    System.put_env("HTTP_BASIC_PASSWORD", "keep-out")

    cfg = Config.get()
    assert cfg.username == "gate"
    assert cfg.password == "keep-out"

    System.delete_env("HTTP_BASIC_USERNAME")
    System.delete_env("HTTP_BASIC_PASSWORD")
    System.put_env("BASIC_AUTH_USERNAME", "basic")
    System.put_env("BASIC_AUTH_PASSWORD", "auth-secret")

    cfg = Config.get()
    assert cfg.username == "basic"
    assert cfg.password == "auth-secret"
  end
end
