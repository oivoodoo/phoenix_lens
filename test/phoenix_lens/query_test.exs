defmodule PhoenixLens.QueryTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.Query

  @moduletag :integration

  setup do
    url = System.get_env("DATABASE_URL")

    pid =
      start_supervised!(%{
        id: :lens_setup_pg,
        start: {Postgrex, :start_link, [postgrex_opts(url)]}
      })

    {:ok, _} = Postgrex.query(pid, "DROP TABLE IF EXISTS lens_users", [])

    {:ok, _} =
      Postgrex.query(
        pid,
        """
        CREATE TABLE lens_users (
          id serial PRIMARY KEY,
          email text NOT NULL,
          first_name text,
          inserted_at timestamp NOT NULL DEFAULT now()
        )
        """,
        []
      )

    {:ok, _} =
      Postgrex.query(
        pid,
        "INSERT INTO lens_users (email, first_name) VALUES ($1, $2)",
        ["alice@example.com", "Alice"]
      )

    previous = Application.get_all_env(:phoenix_lens)
    previous_rules = :persistent_term.get({PhoenixLens.Protection, :rules}, :miss)

    :persistent_term.put(
      {PhoenixLens.Protection, :rules},
      %{global: MapSet.new(), sources: %{}, tables: %{}}
    )

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_lens),
          do: Application.delete_env(:phoenix_lens, key)

      for {key, value} <- previous, do: Application.put_env(:phoenix_lens, key, value)
      :persistent_term.put({PhoenixLens.Protection, :rules}, previous_rules)
    end)

    Application.delete_env(:phoenix_lens, :databases)
    Application.delete_env(:phoenix_lens, :repo)
    Application.put_env(:phoenix_lens, :url, url)
    Application.put_env(:phoenix_lens, :masked_fields, [:email, :first_name])
    Application.put_env(:phoenix_lens, :max_rows, 10_000)
    Application.put_env(:phoenix_lens, :timeout_ms, 5_000)
    Application.put_env(:phoenix_lens, :start_connections, true)

    name = PhoenixLens.Config.connection_name("primary")

    unless Process.whereis(name) do
      start_supervised!(%{
        id: :lens_query_pg,
        start: {Postgrex, :start_link, [Keyword.put(postgrex_opts(url), :name, name)]}
      })
    end

    {:ok, pid: pid}
  end

  test "SELECT runs and masks aliased email" do
    assert {:ok, result} =
             Query.run("SELECT id, email AS contact, first_name FROM lens_users")

    refute inspect(result.rows) =~ "alice@example.com"
    refute inspect(result.rows) =~ "Alice"
    assert "contact" in result.masked_columns
    assert "first_name" in result.masked_columns
    assert hd(hd(result.rows)) != :redacted
  end

  test "DELETE is rejected and does not change data", %{pid: pid} do
    assert {:error, %{kind: :read_only}} = Query.run("DELETE FROM lens_users")
    {:ok, %{rows: [[count]]}} = Postgrex.query(pid, "SELECT count(*) FROM lens_users", [])
    assert count == 1
  end

  test "runtime global protection masks the column" do
    Application.put_env(:phoenix_lens, :masked_fields, [])

    put_protection_rules(%{
      global: MapSet.new(["inserted_at"]),
      sources: %{},
      tables: %{}
    })

    assert {:ok, result} = Query.run("SELECT id, inserted_at FROM lens_users")
    assert "inserted_at" in result.masked_columns
    assert Enum.at(hd(result.rows), 1) == :redacted
    assert hd(hd(result.rows)) != :redacted
  end

  test "runtime table protection masks only that table" do
    Application.put_env(:phoenix_lens, :masked_fields, [])

    put_protection_rules(%{
      global: MapSet.new(),
      sources: %{},
      tables: %{{"primary", "lens_users"} => MapSet.new(["inserted_at"])}
    })

    assert {:ok, result} = Query.run("SELECT id, inserted_at FROM lens_users")
    assert "inserted_at" in result.masked_columns
    assert Enum.at(hd(result.rows), 1) == :redacted
  end

  test "runtime table protection does not mask the same name from another table" do
    Application.put_env(:phoenix_lens, :masked_fields, [])

    put_protection_rules(%{
      global: MapSet.new(),
      sources: %{},
      tables: %{{"primary", "posts"} => MapSet.new(["inserted_at"])}
    })

    assert {:ok, result} = Query.run("SELECT id, inserted_at FROM lens_users")
    refute "inserted_at" in result.masked_columns
    refute Enum.at(hd(result.rows), 1) == :redacted
  end

  test "runtime source protection applies on that database id" do
    Application.put_env(:phoenix_lens, :masked_fields, [])

    put_protection_rules(%{
      global: MapSet.new(),
      sources: %{"primary" => MapSet.new(["inserted_at"])},
      tables: %{}
    })

    assert {:ok, result} = Query.run("SELECT inserted_at FROM lens_users")
    assert "inserted_at" in result.masked_columns
    assert hd(hd(result.rows)) == :redacted
  end

  test "runtime source protection does not apply to another source" do
    Application.put_env(:phoenix_lens, :masked_fields, [])

    put_protection_rules(%{
      global: MapSet.new(),
      sources: %{"warehouse" => MapSet.new(["inserted_at"])},
      tables: %{}
    })

    assert {:ok, result} = Query.run("SELECT inserted_at FROM lens_users")
    refute "inserted_at" in result.masked_columns
  end

  test "aliased protected attribute is still masked" do
    Application.put_env(:phoenix_lens, :masked_fields, [])

    put_protection_rules(%{
      global: MapSet.new(["email"]),
      sources: %{},
      tables: %{}
    })

    assert {:ok, result} = Query.run("SELECT email AS contact FROM lens_users")
    assert "contact" in result.masked_columns
    refute inspect(result.rows) =~ "alice@example.com"
  end

  test "row cap sets truncated" do
    Application.put_env(:phoenix_lens, :max_rows, 0)

    assert {:ok, result} = Query.run("SELECT id FROM lens_users")
    assert result.truncated
    assert result.rows == []

    Application.put_env(:phoenix_lens, :max_rows, 10_000)
  end

  defp put_protection_rules(rules) do
    :persistent_term.put({PhoenixLens.Protection, :rules}, rules)
  end

  defp postgrex_opts(url) do
    uri = URI.parse(url)

    {user, pass} =
      case uri.userinfo do
        nil ->
          {nil, nil}

        info ->
          case String.split(info, ":", parts: 2) do
            [u] -> {u, nil}
            [u, p] -> {u, p}
          end
      end

    db = (uri.path || "/postgres") |> String.trim_leading("/")

    [
      hostname: uri.host || "localhost",
      port: uri.port || 5432,
      username: user,
      password: pass,
      database: db
    ]
  end
end
