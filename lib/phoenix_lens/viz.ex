defmodule PhoenixLens.Viz do
  @moduledoc false

  alias PhoenixLens.Result

  @page_size 25
  @chart_limit 24

  def page_size, do: @page_size

  def page(%Result{} = result, page, page_size) do
    total = length(result.rows)
    page_size = page_size |> max(1)
    pages = max(ceil(total / page_size), 1)
    page = page |> max(1) |> min(pages)
    start = (page - 1) * page_size
    rows = Enum.slice(result.rows, start, page_size)

    %{
      rows: rows,
      page: page,
      page_size: page_size,
      pages: pages,
      total: total,
      from: if(total == 0, do: 0, else: start + 1),
      to: min(start + length(rows), total)
    }
  end

  def default_x(%Result{columns: columns, rows: rows}) do
    idx =
      Enum.find_index(columns, fn col ->
        i = column_index(columns, col)
        not numeric_column?(rows, i)
      end) || 0

    Enum.at(columns, idx)
  end

  def default_y(%Result{columns: columns, rows: rows}) do
    case Enum.find_index(columns, fn col ->
           i = column_index(columns, col)
           numeric_column?(rows, i) and not id_name?(col)
         end) do
      nil -> "__count__"
      idx -> Enum.at(columns, idx)
    end
  end

  defp id_name?(col) do
    down = col |> to_string() |> String.downcase()
    down == "id" or String.ends_with?(down, "_id")
  end

  def series(%Result{} = result, x, y) do
    xi = column_index(result.columns, x)

    cond do
      is_nil(xi) ->
        []

      y == "__count__" ->
        result.rows
        |> Enum.frequencies_by(fn row -> Result.display_cell(Enum.at(row, xi)) end)
        |> Enum.map(fn {label, n} -> {label, n * 1.0} end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(@chart_limit)

      true ->
        yi = column_index(result.columns, y)

        if is_nil(yi) do
          []
        else
          result.rows
          |> Enum.map(fn row ->
            {Result.display_cell(Enum.at(row, xi)), to_number(Enum.at(row, yi))}
          end)
          |> Enum.reject(fn {_l, n} -> is_nil(n) end)
          |> Enum.take(@chart_limit)
        end
    end
  end

  defp column_index(columns, name) do
    Enum.find_index(columns, &(to_string(&1) == to_string(name)))
  end

  defp numeric_column?(rows, idx) when is_integer(idx) do
    rows
    |> Enum.take(30)
    |> Enum.any?(fn row -> match_number?(Enum.at(row, idx)) end)
  end

  defp numeric_column?(_, _), do: false

  defp match_number?(n) when is_number(n), do: true
  defp match_number?(%Decimal{}), do: true
  defp match_number?(_), do: false

  defp to_number(n) when is_number(n), do: n * 1.0
  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(_), do: nil
end
