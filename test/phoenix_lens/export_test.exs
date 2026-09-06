defmodule PhoenixLens.ExportTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.{Export, Result}

  defp result do
    %Result{
      columns: ["id", "email", "total"],
      rows: [[1, :redacted, 12.5], [2, :redacted, 4]],
      masked_columns: ["email"],
      num_rows: 2
    }
  end

  test "CSV includes header, masked cells, and no raw PII" do
    csv = Export.csv(result())
    assert csv =~ "id,email,total"
    assert csv =~ "[redacted]"
    refute csv =~ "alice@"
    assert csv =~ "12.5"
  end

  test "JSON includes columns, masked rows, and masked_columns" do
    {:ok, data} = Jason.decode(Export.json(result()))
    assert data["columns"] == ["id", "email", "total"]
    assert data["masked_columns"] == ["email"]
    assert hd(data["rows"]) == [1, "[redacted]", 12.5]
  end
end
