defmodule PhoenixLens.DuckDBTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.DuckDB

  @moduletag :duckdb

  setup do
    if DuckDB.available?() do
      :ok
    else
      {:skip, "duckdbex is not loaded"}
    end
  end

  test "open_memory and SELECT" do
    assert {:ok, %{conn: conn, db: db}} = DuckDB.open_memory()
    assert {:ok, result} = DuckDB.query(conn, "SELECT 1 AS n, 'ok' AS label")
    assert result.columns == ["n", "label"]
    assert result.rows == [[1, "ok"]]
    _ = Duckdbex.release(conn)
    _ = Duckdbex.release(db)
  end

  test "attaches a CSV file as a view" do
    path = Path.join(System.tmp_dir!(), "lens_people_#{System.unique_integer([:positive])}.csv")
    File.write!(path, "id,name\n1,ada\n2,grace\n")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, %{conn: conn, db: db}} = DuckDB.open_memory()

    source = %{
      id: nil,
      alias: "people",
      kind: "csv",
      dsn: path,
      builtin?: false,
      label: "people",
      error: nil,
      ok?: nil
    }

    assert :ok = DuckDB.attach_one(conn, source)
    assert {:ok, result} = DuckDB.query(conn, "SELECT name FROM people ORDER BY id")
    names = Enum.map(result.rows, &List.last/1)
    assert names == ["ada", "grace"]

    tables = DuckDB.tables(conn)
    assert Enum.any?(tables, &(&1.name == "people"))

    _ = Duckdbex.release(conn)
    _ = Duckdbex.release(db)
  end

  test "user SQL cannot ATTACH via the validator" do
    assert {:error, %{kind: :read_only}} =
             PhoenixLens.SQL.validate("ATTACH 'foo.db' AS other")
  end
end
