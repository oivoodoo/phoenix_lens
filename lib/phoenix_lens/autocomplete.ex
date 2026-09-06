defmodule PhoenixLens.Autocomplete do
  @moduledoc false

  alias PhoenixLens.{Catalog, Config, Policy}

  @keywords ~w(
    SELECT FROM WHERE GROUP BY ORDER LIMIT OFFSET JOIN LEFT RIGHT INNER
    OUTER FULL CROSS ON AND OR NOT AS DISTINCT COUNT SUM AVG MIN MAX
    HAVING UNION ALL EXISTS IN IS NULL TRUE FALSE CASE WHEN THEN ELSE
    END ASC DESC WITH
  )

  @table_context ~w(FROM JOIN INTO UPDATE TABLE)

  def catalog do
    schemas = Catalog.schemas()

    from_ecto =
      Enum.map(schemas, fn s ->
        %{
          name: s.source,
          columns:
            Enum.map(s.fields, fn f ->
              %{name: f.name, protected: f.protected, type: f.type}
            end)
        }
      end)

    merge_tables(from_ecto, db_tables_as_catalog())
  end

  def payload(tables \\ catalog()) do
    %{tables: tables, keywords: @keywords}
  end

  def suggest(tables, sql, cursor) when is_binary(sql) and is_integer(cursor) do
    cursor = sql |> String.length() |> min(max(cursor, 0))
    left = String.slice(sql, 0, cursor)
    {prefix, table_qual, context} = context(left)
    prefix_down = String.downcase(prefix)

    if prefix_down == "" and context == :any do
      []
    else
      candidates(tables, context, table_qual)
      |> Enum.filter(&matches?(&1.value, prefix_down))
      |> Enum.sort_by(&rank(&1.value, prefix_down))
      |> Enum.take(12)
    end
  end

  defp context(left) do
    cond do
      match = Regex.run(~r/([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z0-9_]*)$/, left) ->
        [_, table, col] = match
        {col, String.downcase(table), :column}

      true ->
        prefix =
          case Regex.run(~r/[A-Za-z0-9_]*$/, left) do
            [p] -> p
            _ -> ""
          end

        before =
          left
          |> String.slice(0, max(String.length(left) - String.length(prefix), 0))
          |> String.trim_trailing()
          |> String.upcase()

        prev =
          case Regex.run(~r/([A-Z]+)$/, before) do
            [_, word] -> word
            _ -> ""
          end

        ctx = if prev in @table_context, do: :table, else: :any
        {prefix, nil, ctx}
    end
  end

  defp candidates(tables, :table, _) do
    Enum.map(tables, &table_item/1)
  end

  defp candidates(tables, :column, table_name) do
    case Enum.find(tables, &(String.downcase(&1.name) == table_name)) do
      nil -> []
      table -> Enum.map(table.columns, &column_item(&1, table.name))
    end
  end

  defp candidates(tables, :any, _) do
    table_items = Enum.map(tables, &table_item/1)

    column_items =
      Enum.flat_map(tables, fn t ->
        Enum.map(t.columns, &column_item(&1, t.name))
      end)

    keyword_items =
      Enum.map(@keywords, fn k ->
        %{value: k, kind: "keyword", detail: "keyword", protected: false}
      end)

    table_items ++ column_items ++ keyword_items
  end

  defp table_item(table) do
    %{value: table.name, kind: "table", detail: "table", protected: false}
  end

  defp column_item(col, table) do
    detail =
      [table, col.name]
      |> Enum.join(".")
      |> then(fn ident ->
        if col.protected, do: ident <> " · redacted", else: ident
      end)

    %{value: col.name, kind: "column", detail: detail, protected: col.protected == true}
  end

  defp matches?(_value, ""), do: true
  defp matches?(value, prefix), do: String.starts_with?(String.downcase(value), prefix)

  defp rank(value, prefix) do
    down = String.downcase(value)

    cond do
      down == prefix -> 0
      String.starts_with?(down, prefix) -> 1
      true -> 2
    end
  end

  defp merge_tables(primary, extra) do
    by_name = Map.new(primary, fn t -> {String.downcase(t.name), t} end)

    Enum.reduce(extra, by_name, fn table, acc ->
      key = String.downcase(table.name)

      Map.update(acc, key, table, fn existing ->
        cols =
          (existing.columns ++ table.columns)
          |> Enum.uniq_by(&String.downcase(&1.name))

        %{existing | columns: cols}
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  defp db_tables_as_catalog do
    protected = Policy.protected_set(Config.get())

    Enum.map(Catalog.database_tables(), fn table ->
      %{
        name: table.name,
        columns:
          Enum.map(table.columns, fn col ->
            %{
              name: col.name,
              protected: MapSet.member?(protected, String.downcase(col.name)),
              type: col.type
            }
          end)
      }
    end)
  end
end
