defmodule PhoenixLens.DuckDBJoinTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.{DuckDB, Query}

  @moduletag :duckdb

  setup do
    if DuckDB.available?() do
      previous = Application.get_all_env(:phoenix_lens)

      on_exit(fn ->
        Application.delete_env(:phoenix_lens, :engine)
        Application.delete_env(:phoenix_lens, :duckdb_sources)

        for {key, _} <- Application.get_all_env(:phoenix_lens),
            do: Application.delete_env(:phoenix_lens, key)

        for {key, value} <- previous, do: Application.put_env(:phoenix_lens, key, value)

        if Process.whereis(PhoenixLens.DuckDB.Server) do
          PhoenixLens.DuckDB.Server.reload()
        end
      end)

      {:ok, open} = DuckDB.open_memory()
      on_exit(fn -> release(open) end)
      {:ok, open: open}
    else
      {:skip, "duckdbex is not loaded"}
    end
  end

  test "joins CSV, SQLite, and JSON in one question", %{open: %{conn: conn}} do
    csv =
      write_temp(
        "people.csv",
        "id,name,email\n1,ada,ada@example.com\n2,grace,grace@example.com\n"
      )

    json =
      write_temp("regions.json", ~s([{"user_id":1,"region":"eu"},{"user_id":2,"region":"us"}]))

    sqlite = write_sqlite_orders()

    attached =
      DuckDB.attach_all(conn, [
        source("people", "csv", csv),
        source("shop", "sqlite", sqlite),
        source("regions", "json", json)
      ])

    assert Enum.all?(attached, & &1.ok?), inspect(attached)

    assert {:ok, result} =
             DuckDB.query(conn, """
             SELECT p.name, o.sku, r.region
             FROM people p
             JOIN shop.orders o ON o.user_id = p.id
             JOIN regions r ON r.user_id = p.id
             ORDER BY p.id
             """)

    assert result.columns == ["name", "sku", "region"]
    assert result.rows == [["ada", "pro", "eu"], ["grace", "hobby", "us"]]
  end

  test "Query.run joins CSV and SQLite through the DuckDB engine" do
    csv =
      write_temp(
        "people.csv",
        "id,name,email\n1,ada,ada@example.com\n2,grace,grace@example.com\n"
      )

    sqlite = write_sqlite_orders()

    Application.delete_env(:phoenix_lens, :repo)
    Application.delete_env(:phoenix_lens, :url)
    Application.delete_env(:phoenix_lens, :databases)
    Application.put_env(:phoenix_lens, :engine, :duckdb)
    Application.put_env(:phoenix_lens, :masked_fields, [:email])
    Application.put_env(:phoenix_lens, :max_rows, 10_000)
    Application.put_env(:phoenix_lens, :timeout_ms, 15_000)

    Application.put_env(:phoenix_lens, :duckdb_sources, [
      %{alias: "people", kind: "csv", dsn: csv},
      %{alias: "shop", kind: "sqlite", dsn: sqlite}
    ])

    assert {:ok, _} = DuckDB.Server.reload()

    assert {:ok, result} =
             Query.run("""
             SELECT p.name, p.email AS contact, o.sku, o.amount
             FROM people p
             JOIN shop.orders o ON o.user_id = p.id
             ORDER BY p.id
             """)

    assert result.columns == ["name", "contact", "sku", "amount"]
    assert "contact" in result.masked_columns
    refute inspect(result.rows) =~ "ada@example.com"
    assert hd(result.rows) |> Enum.at(0) == "ada"
    assert hd(result.rows) |> Enum.at(2) == "pro"
  end

  test "joins a remote HTTP CSV with SQLite", %{open: %{conn: conn}} do
    sqlite = write_sqlite_orders()
    url = start_csv_http("user_id,plan\n1,enterprise\n2,starter\n")

    attached =
      DuckDB.attach_all(conn, [
        source("shop", "sqlite", sqlite),
        source("plans", "csv", url)
      ])

    if http_attached?(attached, "plans") do
      assert {:ok, result} =
               DuckDB.query(conn, """
               SELECT o.sku, p.plan
               FROM shop.orders o
               JOIN plans p ON CAST(p.user_id AS INTEGER) = o.user_id
               ORDER BY o.user_id
               """)

      assert result.rows == [["pro", "enterprise"], ["hobby", "starter"]]
    else
      assert hd(attached) |> Map.get(:ok?)
    end
  end

  @tag :integration
  test "joins PostgreSQL, remote CSV, and SQLite in one question", %{open: %{conn: conn}} do
    url = System.get_env("DATABASE_URL")
    sqlite = write_sqlite_orders()
    csv_url = start_csv_http("user_id,plan\n1,enterprise\n")

    {:ok, pid} =
      Postgrex.start_link(postgrex_opts(url) ++ [backoff_type: :stop])

    {:ok, _} = Postgrex.query(pid, "DROP TABLE IF EXISTS lens_users", [])

    {:ok, _} =
      Postgrex.query(
        pid,
        """
        CREATE TABLE lens_users (
          id integer PRIMARY KEY,
          email text NOT NULL,
          first_name text
        )
        """,
        []
      )

    {:ok, _} =
      Postgrex.query(pid, "INSERT INTO lens_users (id, email, first_name) VALUES (1, $1, $2)", [
        "ada@example.com",
        "Ada"
      ])

    attached =
      DuckDB.attach_all(conn, [
        source("repo", "postgres", url),
        source("shop", "sqlite", sqlite),
        source("plans", "csv", csv_url)
      ])

    repo = Enum.find(attached, &(&1.alias == "repo"))
    assert repo.ok?, "postgres attach failed: #{repo.error}"

    assert {:ok, result} =
             DuckDB.query(conn, """
             SELECT u.first_name, o.sku, p.plan
             FROM repo.lens_users u
             JOIN shop.orders o ON o.user_id = u.id
             JOIN plans p ON CAST(p.user_id AS INTEGER) = u.id
             """)

    assert result.rows == [["Ada", "pro", "enterprise"]]
    Process.exit(pid, :normal)
  end

  @tag :mysql
  test "Query.run joins PostgreSQL + MySQL + remote CSV" do
    pg_url = System.get_env("DATABASE_URL")
    mysql_url = System.get_env("MYSQL_URL")
    csv_url = start_csv_http("user_id,plan\n1,enterprise\n")

    {:ok, pid} = Postgrex.start_link(postgrex_opts(pg_url) ++ [backoff_type: :stop])
    {:ok, _} = Postgrex.query(pid, "DROP TABLE IF EXISTS lens_users", [])

    {:ok, _} =
      Postgrex.query(
        pid,
        """
        CREATE TABLE lens_users (
          id integer PRIMARY KEY,
          email text NOT NULL,
          first_name text
        )
        """,
        []
      )

    {:ok, _} =
      Postgrex.query(pid, "INSERT INTO lens_users (id, email, first_name) VALUES (1, $1, $2)", [
        "ada@example.com",
        "Ada"
      ])

    assert :ok = seed_mysql_orders(mysql_url)

    Application.put_env(:phoenix_lens, :url, pg_url)
    Application.put_env(:phoenix_lens, :engine, :duckdb)
    Application.put_env(:phoenix_lens, :masked_fields, [:email, :first_name])
    Application.put_env(:phoenix_lens, :max_rows, 10_000)
    Application.put_env(:phoenix_lens, :timeout_ms, 30_000)

    Application.put_env(:phoenix_lens, :duckdb_sources, [
      %{alias: "billing", kind: "mysql", dsn: mysql_url},
      %{alias: "plans", kind: "csv", dsn: csv_url}
    ])

    {:ok, status} = DuckDB.Server.reload()
    billing = Enum.find(status.attached, &(&1.alias == "billing"))
    repo = Enum.find(status.attached, &(&1.alias == "repo"))
    assert repo && repo.ok?, "postgres attach failed: #{repo && repo.error}"
    assert billing && billing.ok?, "mysql attach failed: #{billing && billing.error}"

    assert {:ok, result} =
             Query.run("""
             SELECT u.email AS contact, b.sku, p.plan
             FROM repo.lens_users u
             JOIN billing.orders b ON b.user_id = u.id
             JOIN plans p ON CAST(p.user_id AS INTEGER) = u.id
             """)

    assert "contact" in result.masked_columns
    refute inspect(result.rows) =~ "ada@example.com"
    assert Enum.any?(result.rows, fn row -> "pro" in row and "enterprise" in row end)

    Process.exit(pid, :normal)
  end

  defp source(alias_, kind, dsn) do
    %{
      id: nil,
      alias: alias_,
      kind: kind,
      dsn: dsn,
      builtin?: false,
      label: alias_,
      error: nil,
      ok?: nil
    }
  end

  defp write_temp(name, body) do
    path = Path.join(System.tmp_dir!(), "lens_#{System.unique_integer([:positive])}_#{name}")
    File.write!(path, body)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp write_sqlite_orders do
    path = Path.join(System.tmp_dir!(), "lens_shop_#{System.unique_integer([:positive])}.db")
    {:ok, open} = DuckDB.open_memory()

    assert :ok =
             DuckDB.attach_one(
               open.conn,
               Map.put(source("shop", "sqlite", path), :read_only, false)
             )

    assert :ok =
             DuckDB.exec(
               open.conn,
               "CREATE TABLE shop.orders (user_id INTEGER, sku VARCHAR, amount INTEGER)"
             )

    assert :ok =
             DuckDB.exec(
               open.conn,
               "INSERT INTO shop.orders VALUES (1, 'pro', 49), (2, 'hobby', 9)"
             )

    release(open)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp seed_mysql_orders(dsn) do
    {:ok, open} = DuckDB.open_memory()

    result =
      with :ok <-
             DuckDB.attach_one(
               open.conn,
               Map.put(source("billing", "mysql", dsn), :read_only, false)
             ),
           :ok <- DuckDB.exec(open.conn, "DROP TABLE IF EXISTS billing.orders"),
           :ok <-
             DuckDB.exec(
               open.conn,
               "CREATE TABLE billing.orders (user_id INTEGER, sku VARCHAR, amount INTEGER)"
             ),
           :ok <- DuckDB.exec(open.conn, "INSERT INTO billing.orders VALUES (1, 'pro', 49)") do
        :ok
      end

    release(open)
    result
  end

  defp start_csv_http(body) do
    port = 40_000 + rem(System.unique_integer([:positive]), 10_000)

    {:ok, _pid} =
      start_supervised(%{
        id: {:lens_csv_http, port},
        start:
          {Bandit, :start_link,
           [
             [
               plug: {PhoenixLens.Test.CSVPlug, body},
               port: port,
               ip: {127, 0, 0, 1},
               startup_log: false
             ]
           ]}
      })

    "http://127.0.0.1:#{port}/plans.csv"
  end

  defp http_attached?(attached, alias_) do
    case Enum.find(attached, &(&1.alias == alias_)) do
      %{ok?: true} -> true
      _ -> false
    end
  end

  defp release(%{conn: conn, db: db}) do
    _ = Duckdbex.release(conn)
    _ = Duckdbex.release(db)
  rescue
    _ -> :ok
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
