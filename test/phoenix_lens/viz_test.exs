defmodule PhoenixLens.VizTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.{Result, Viz}

  defp posts do
    %Result{
      columns: ["id", "title", "category", "status"],
      rows: [
        [1, "A", "ops", "published"],
        [2, "B", "ops", "draft"],
        [3, "C", "design", "published"]
      ],
      masked_columns: [],
      num_rows: 3
    }
  end

  defp metrics do
    %Result{
      columns: ["day", "count"],
      rows:
        [[{"2026-01-01", 10}, {"2026-01-02", 4}] |> Enum.map(&Tuple.to_list/1)]
        |> then(fn _ -> [["2026-01-01", 10], ["2026-01-02", 4]] end),
      masked_columns: [],
      num_rows: 2
    }
  end

  test "paginates rows" do
    result = %Result{
      columns: ["id"],
      rows: Enum.map(1..30, &[&1]),
      masked_columns: [],
      num_rows: 30
    }

    page = Viz.page(result, 2, 10)
    assert page.rows == Enum.map(11..20, &[&1])
    assert page.total == 30
    assert page.page == 2
    assert page.pages == 3
  end

  test "defaults X to a low-cardinality category and Y to count when no metric" do
    assert Viz.default_x(posts()) in ["category", "status"]
    assert Viz.default_y(posts()) == "__count__"
  end

  test "line charts prefer a time column for X" do
    result = %Result{
      columns: ["body", "inserted_at", "n"],
      rows: [
        ["hello", ~U[2026-01-01 00:00:00Z], 3],
        ["hi", ~U[2026-01-02 00:00:00Z], 5]
      ],
      masked_columns: [],
      num_rows: 2
    }

    assert Viz.default_x(result, "line") == "inserted_at"
    assert Viz.default_y(result, "line") == "n"
  end

  test "falls back to count when Y is not numeric" do
    pairs = Viz.series(posts(), "category", "title")
    assert {"ops", 2.0} in pairs
  end

  test "skips masked columns as Y" do
    result = %Result{
      columns: ["id", "body", "author_email"],
      rows: [[1, "hi", :redacted], [2, "yo", :redacted]],
      masked_columns: ["author_email"],
      num_rows: 2
    }

    {_x, y} = Viz.coerce_axes(result, "body", "author_email", "line")
    assert y == "__count__"
    assert Viz.series(result, "body", y) != []
  end

  test "defaults Y to first numeric column" do
    assert Viz.default_x(metrics()) == "day"
    assert Viz.default_y(metrics()) == "count"
  end

  test "count series groups categorical X" do
    pairs = Viz.series(posts(), "category", "__count__")
    assert {"ops", 2.0} in pairs
    assert {"design", 1.0} in pairs
  end

  test "metric series uses X and Y columns" do
    assert Viz.series(metrics(), "day", "count") == [{"2026-01-01", 10.0}, {"2026-01-02", 4.0}]
  end
end
