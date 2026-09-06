defmodule PhoenixLens.NotebookTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Notebook

  test "requires a table" do
    assert {:error, _} = Notebook.to_sql(%Notebook{})
  end

  test "raw table is SELECT * with limit" do
    nb = %Notebook{table: "posts", limit: 100}
    assert {:ok, sql} = Notebook.to_sql(nb)
    assert sql =~ ~s[SELECT *]
    assert sql =~ "LIMIT 100"
  end

  test "filters compile to WHERE" do
    nb = %Notebook{
      table: "posts",
      filters: [%{column: "status", op: "=", value: "published"}],
      limit: 50
    }

    assert {:ok, sql} = Notebook.to_sql(nb)
    assert sql =~ ~s[WHERE "status" = 'published']
  end

  test "contains filter uses ILIKE" do
    nb = %Notebook{
      table: "posts",
      filters: [%{column: "title", op: "contains", value: "lens"}]
    }

    assert {:ok, sql} = Notebook.to_sql(nb)
    assert sql =~ ~s[ILIKE '%lens%']
  end

  test "count of rows with breakout groups" do
    nb = %Notebook{
      table: "posts",
      aggregations: [%{fun: "count", column: nil}],
      breakouts: ["category"]
    }

    assert {:ok, sql} = Notebook.to_sql(nb)
    assert sql =~ ~s[SELECT "category", count(*) AS "count"]
    assert sql =~ ~s[GROUP BY "category"]
  end

  test "sum of a column" do
    nb = %Notebook{
      table: "orders",
      aggregations: [%{fun: "sum", column: "total_cents"}]
    }

    assert {:ok, sql} = Notebook.to_sql(nb)
    assert sql =~ ~s[sum("total_cents") AS "sum_total_cents"]
  end

  test "rejects unsafe identifiers" do
    nb = %Notebook{table: "posts; drop"}
    assert {:error, _} = Notebook.to_sql(nb)
  end

  test "quotes dotted DuckDB table names" do
    nb = %Notebook{table: "repo.users", limit: 10}
    assert {:ok, sql} = Notebook.to_sql(nb)
    assert sql =~ ~s[FROM "repo"."users"]
    assert sql =~ "LIMIT 10"
  end

  test "quotes string literals" do
    nb = %Notebook{
      table: "posts",
      filters: [%{column: "title", op: "=", value: "it's"}]
    }

    assert {:ok, sql} = Notebook.to_sql(nb)
    assert sql =~ "'it''s'"
  end
end
