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

  test "defaults X to first non-numeric column and Y to count when no metric" do
    assert Viz.default_x(posts()) == "title"
    assert Viz.default_y(posts()) == "__count__"
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
