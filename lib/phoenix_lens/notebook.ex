defmodule PhoenixLens.Notebook do
  @moduledoc false

  defstruct table: nil,
            filters: [],
            aggregations: [],
            breakouts: [],
            sorts: [],
            limit: 100

  @type t :: %__MODULE__{
          table: String.t() | nil,
          filters: [map()],
          aggregations: [map()],
          breakouts: [String.t()],
          sorts: [map()],
          limit: pos_integer() | nil
        }

  @ops ~w(= != > < >= <= contains is_null not_null)
  @funs ~w(count sum avg min max)

  def new, do: %__MODULE__{}

  def to_sql(%__MODULE__{table: table}) when not is_binary(table) or table == "" do
    {:error, %PhoenixLens.Error{message: "Pick a table to query", kind: :sql}}
  end

  def to_sql(%__MODULE__{} = nb) do
    with :ok <- ident_ok(nb.table),
         {:ok, where} <- where_sql(nb.filters),
         {:ok, select, group} <- select_sql(nb),
         {:ok, order} <- order_sql(nb.sorts) do
      parts =
        [select, "FROM #{quote_ident(nb.table)}"]
        |> maybe_add(where)
        |> maybe_add(group)
        |> maybe_add(order)
        |> maybe_add(limit_sql(nb.limit))

      {:ok, Enum.join(parts, "\n")}
    end
  end

  def pick_table(%__MODULE__{} = nb, table) do
    %{nb | table: table, filters: [], aggregations: [], breakouts: [], sorts: []}
  end

  defp select_sql(%__MODULE__{aggregations: [], breakouts: []}) do
    {:ok, "SELECT *", nil}
  end

  defp select_sql(%__MODULE__{} = nb) do
    with :ok <- Enum.reduce_while(nb.breakouts, :ok, fn col, _ -> ident_reduce(col) end),
         {:ok, aggs} <- agg_sql(nb.aggregations) do
      breakouts = Enum.map(nb.breakouts, &quote_ident/1)
      select = (breakouts ++ aggs) |> Enum.join(", ")
      group = if nb.breakouts == [], do: nil, else: "GROUP BY " <> Enum.join(breakouts, ", ")
      {:ok, "SELECT " <> select, group}
    end
  end

  defp agg_sql([]), do: {:ok, ["count(*) AS \"count\""]}

  defp agg_sql(aggs) do
    Enum.reduce_while(aggs, {:ok, []}, fn agg, {:ok, acc} ->
      case compile_agg(agg) do
        {:ok, sql} -> {:cont, {:ok, acc ++ [sql]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp compile_agg(%{fun: fun} = agg) do
    fun = fun |> to_string() |> String.downcase()

    cond do
      fun not in @funs ->
        {:error, %PhoenixLens.Error{message: "Unknown summary #{fun}", kind: :sql}}

      fun == "count" ->
        {:ok, "count(*) AS \"count\""}

      true ->
        col = agg[:column] || agg["column"]

        with :ok <- ident_ok(col) do
          {:ok, "#{fun}(#{quote_ident(col)}) AS \"#{fun}_#{col}\""}
        end
    end
  end

  defp compile_agg(_), do: {:error, %PhoenixLens.Error{message: "Invalid summary", kind: :sql}}

  defp where_sql(filters) do
    clauses =
      filters
      |> Enum.map(&filter_sql/1)
      |> Enum.reject(&is_nil/1)

    errors = Enum.find(clauses, &match?({:error, _}, &1))

    cond do
      errors ->
        errors

      clauses == [] ->
        {:ok, nil}

      true ->
        parts = Enum.map(clauses, fn {:ok, sql} -> sql end)
        {:ok, "WHERE " <> Enum.join(parts, " AND ")}
    end
  end

  defp filter_sql(%{column: col} = f) when is_binary(col) and col != "" do
    op = f[:op] || f["op"] || "="
    value = f[:value] || f["value"]

    with :ok <- ident_ok(col),
         :ok <- op_ok(op) do
      ident = quote_ident(col)

      sql =
        case op do
          "contains" -> "#{ident} ILIKE #{quote_like(value)}"
          "is_null" -> "#{ident} IS NULL"
          "not_null" -> "#{ident} IS NOT NULL"
          "=" -> "#{ident} = #{quote_value(value)}"
          "!=" -> "#{ident} <> #{quote_value(value)}"
          other -> "#{ident} #{other} #{quote_value(value)}"
        end

      {:ok, sql}
    end
  end

  defp filter_sql(_), do: nil

  defp order_sql([]), do: {:ok, nil}

  defp order_sql(sorts) do
    Enum.reduce_while(sorts, {:ok, []}, fn sort, {:ok, acc} ->
      col = sort[:column] || sort["column"]
      dir = if (sort[:dir] || sort["dir"]) == "desc", do: "DESC", else: "ASC"

      case ident_ok(col) do
        :ok -> {:cont, {:ok, acc ++ ["#{quote_ident(col)} #{dir}"]}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, []} -> {:ok, nil}
      {:ok, parts} -> {:ok, "ORDER BY " <> Enum.join(parts, ", ")}
      other -> other
    end
  end

  defp limit_sql(n) when is_integer(n) and n > 0 and n <= 10_000, do: "LIMIT #{n}"
  defp limit_sql(_), do: nil

  defp maybe_add(parts, nil), do: parts
  defp maybe_add(parts, part), do: parts ++ [part]

  defp ident_reduce(col) do
    case ident_ok(col) do
      :ok -> {:cont, :ok}
      err -> {:halt, err}
    end
  end

  defp ident_ok(name) when is_binary(name) do
    if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*){0,3}\z/, name) do
      :ok
    else
      {:error, %PhoenixLens.Error{message: "Invalid identifier", kind: :sql}}
    end
  end

  defp ident_ok(_), do: {:error, %PhoenixLens.Error{message: "Invalid identifier", kind: :sql}}

  defp op_ok(op) when op in @ops, do: :ok
  defp op_ok(_), do: {:error, %PhoenixLens.Error{message: "Invalid filter operator", kind: :sql}}

  defp quote_ident(name) do
    name
    |> to_string()
    |> String.split(".")
    |> Enum.map_join(".", fn part -> "\"" <> String.replace(part, "\"", "\"\"") <> "\"" end)
  end

  defp quote_value(v) when is_integer(v), do: Integer.to_string(v)
  defp quote_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 6)

  defp quote_value(v) do
    s = v |> to_string() |> String.replace("'", "''")
    "'#{s}'"
  end

  defp quote_like(v) do
    s =
      v
      |> to_string()
      |> String.replace("'", "''")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "'%#{s}%'"
  end
end
