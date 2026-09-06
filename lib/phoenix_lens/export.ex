defmodule PhoenixLens.Export do
  @moduledoc false

  alias PhoenixLens.Result

  def csv(%Result{} = result) do
    header = Enum.map_join(result.columns, ",", &escape/1)

    rows =
      Enum.map_join(result.rows, "\n", fn row ->
        Enum.map_join(row, ",", fn cell -> escape(Result.display_cell(cell)) end)
      end)

    header <> "\n" <> rows <> "\n"
  end

  def json(%Result{} = result) do
    rows =
      Enum.map(result.rows, fn row ->
        Enum.map(row, &json_cell/1)
      end)

    Jason.encode!(%{
      columns: result.columns,
      rows: rows,
      masked_columns: result.masked_columns
    })
  end

  defp json_cell(:redacted), do: Result.redacted_label()
  defp json_cell(nil), do: nil
  defp json_cell(value) when is_number(value) or is_boolean(value), do: value
  defp json_cell(value), do: Result.display_cell(value)

  defp escape(value) do
    value = to_string(value)

    if String.contains?(value, [",", "\"", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end
end
