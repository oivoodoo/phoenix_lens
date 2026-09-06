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

  def default_x(result, viz \\ "bar")

  def default_x(%Result{} = result, viz) do
    {x, _y} = coerce_axes(result, nil, nil, viz)
    x
  end

  def default_y(%Result{} = result, viz \\ "bar") do
    {_x, y} = coerce_axes(result, nil, nil, viz)
    y
  end

  def coerce_axes(%Result{} = result, x, y, viz \\ "bar") do
    x = if valid_x?(result, x), do: to_string(x), else: pick_x(result, viz)
    y = if valid_y?(result, y), do: to_string(y), else: pick_y(result)
    {x, y}
  end

  def numeric_columns(%Result{} = result) do
    result.columns
    |> Enum.with_index()
    |> Enum.filter(fn {col, i} ->
      not masked?(result, col) and numeric_column?(result.rows, i) and not id_name?(col)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  def series(%Result{} = result, x, y) do
    pairs = raw_series(result, x, y)

    if pairs == [] and y != "__count__" do
      raw_series(result, x, "__count__")
    else
      pairs
    end
  end

  defp raw_series(%Result{} = result, x, y) do
    xi = column_index(result.columns, x)

    cond do
      is_nil(xi) ->
        []

      y == "__count__" ->
        result.rows
        |> Enum.frequencies_by(fn row -> Result.display_cell(Enum.at(row, xi)) end)
        |> Enum.reject(fn {label, _} -> label in ["", nil] end)
        |> Enum.map(fn {label, n} -> {label, n * 1.0} end)
        |> sort_series(x, result)
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
          |> Enum.reject(fn {l, n} -> is_nil(n) or l in ["", nil] end)
          |> Enum.take(@chart_limit)
        end
    end
  end

  defp pick_x(%Result{columns: columns, rows: rows} = result, viz) do
    indexed = Enum.with_index(columns)
    temporal = find_col(indexed, fn {_c, i} -> temporal_column?(rows, i) end)
    category = best_category(result, indexed)

    text =
      find_col(indexed, fn {col, i} ->
        not masked?(result, col) and not numeric_column?(rows, i)
      end)

    cond do
      viz in ["line", "combo"] and is_binary(temporal) -> temporal
      is_binary(category) -> category
      is_binary(temporal) -> temporal
      is_binary(text) -> text
      true -> List.first(columns)
    end
  end

  defp pick_y(%Result{} = result) do
    case numeric_columns(result) do
      [col | _] -> col
      [] -> "__count__"
    end
  end

  defp best_category(%Result{rows: rows} = result, indexed) do
    indexed
    |> Enum.map(fn {col, i} ->
      uniq =
        rows
        |> Enum.map(&Result.display_cell(Enum.at(&1, i)))
        |> Enum.uniq()
        |> length()

      {col, i, uniq}
    end)
    |> Enum.filter(fn {col, i, uniq} ->
      uniq >= 2 and uniq <= 24 and not masked?(result, col) and
        not numeric_column?(rows, i) and not temporal_column?(rows, i)
    end)
    |> Enum.min_by(fn {_col, _i, uniq} -> uniq end, fn -> nil end)
    |> case do
      {col, _, _} -> col
      nil -> nil
    end
  end

  defp valid_x?(%Result{} = result, x) when is_binary(x) and x != "" do
    not is_nil(column_index(result.columns, x))
  end

  defp valid_x?(_, _), do: false

  defp valid_y?(_result, "__count__"), do: true

  defp valid_y?(%Result{} = result, y) when is_binary(y) and y != "" do
    i = column_index(result.columns, y)
    not is_nil(i) and not masked?(result, y) and numeric_column?(result.rows, i)
  end

  defp valid_y?(_, _), do: false

  defp find_col(indexed, fun) do
    case Enum.find(indexed, fun) do
      {col, _} -> col
      _ -> nil
    end
  end

  defp masked?(%Result{masked_columns: masked}, col) do
    Enum.any?(masked || [], &(to_string(&1) == to_string(col)))
  end

  defp id_name?(col) do
    down = col |> to_string() |> String.downcase()
    down == "id" or String.ends_with?(down, "_id")
  end

  defp column_index(columns, name) do
    Enum.find_index(columns, &(to_string(&1) == to_string(name)))
  end

  defp numeric_column?(rows, idx) when is_integer(idx) do
    sample =
      rows
      |> Enum.take(40)
      |> Enum.map(&Enum.at(&1, idx))
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == :redacted))

    sample != [] and Enum.all?(sample, &match_number?/1)
  end

  defp numeric_column?(_, _), do: false

  defp temporal_column?(rows, idx) when is_integer(idx) do
    rows
    |> Enum.take(30)
    |> Enum.any?(fn row -> temporal?(Enum.at(row, idx)) end)
  end

  defp temporal_column?(_, _), do: false

  defp temporal?(%DateTime{}), do: true
  defp temporal?(%NaiveDateTime{}), do: true
  defp temporal?(%Date{}), do: true
  defp temporal?(s) when is_binary(s), do: Regex.match?(~r/\A\d{4}-\d{2}-\d{2}/, s)
  defp temporal?(_), do: false

  defp match_number?(n) when is_number(n), do: true
  defp match_number?(%Decimal{}), do: true

  defp match_number?(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp match_number?(_), do: false

  defp to_number(n) when is_number(n), do: n * 1.0
  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)

  defp to_number(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {f, ""} -> f
      _ -> nil
    end
  end

  defp to_number(_), do: nil

  defp sort_series(pairs, x, %Result{rows: rows, columns: columns}) do
    i = column_index(columns, x)

    if i && temporal_column?(rows, i) do
      Enum.sort_by(pairs, &elem(&1, 0))
    else
      Enum.sort_by(pairs, &elem(&1, 1), :desc)
    end
  end
end
