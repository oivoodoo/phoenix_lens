defmodule PhoenixLens.ClickhouseAttachTest do
  use ExUnit.Case, async: true

  test "clickhouse attach is read-only and scoped to the URI database" do
    source = %{
      kind: "clickhouse",
      alias: "clickhouse",
      dsn: "clickhouse://datafs:secret@clickhouse:9000/datafs"
    }

    assert PhoenixLens.DuckDB.attach_statement(source) ==
             "ATTACH 'clickhouse://datafs:secret@clickhouse:9000/datafs' AS \"clickhouse\" (TYPE clickhouse, READ_ONLY, SCHEMA 'datafs')"
  end
end
