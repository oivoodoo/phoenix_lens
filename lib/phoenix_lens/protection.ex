defmodule PhoenixLens.Protection do
  @moduledoc """
  Runtime column protection: global, per source, and per table.
  Additive to `config :phoenix_lens, masked_fields`.
  """

  alias PhoenixLens.{Config, Error, SQL}

  @cache {__MODULE__, :rules}
  @scopes ~w(global source table)

  def scopes, do: @scopes

  def rules do
    case :persistent_term.get(@cache, :miss) do
      :miss -> reload()
      rules -> rules
    end
  end

  def reload do
    rules = load_rules()
    :persistent_term.put(@cache, rules)
    rules
  rescue
    _ ->
      empty = empty_rules()
      :persistent_term.put(@cache, empty)
      empty
  end

  def names(database_id \\ "primary", tables \\ []) do
    rules = rules()
    db = database_id |> to_string() |> String.downcase()

    source_names = Map.get(rules.sources, db, MapSet.new())

    table_names =
      Enum.reduce(List.wrap(tables), MapSet.new(), fn table, acc ->
        MapSet.union(acc, table_names(rules, db, table))
      end)

    rules.global
    |> MapSet.union(source_names)
    |> MapSet.union(table_names)
  end

  def names_for_sql(database_id, sql) when is_binary(sql) do
    names(database_id, SQL.table_refs(sql))
  end

  def column_protected?(name, source_id \\ "primary", table \\ nil) do
    n = down(name)
    db = down(source_id || "primary")
    rules = rules()

    MapSet.member?(rules.global, n) or
      MapSet.member?(Map.get(rules.sources, db, MapSet.new()), n) or
      (is_binary(table) and
         MapSet.member?(table_names(rules, db, %{source: db, table: down(table)}), n))
  end

  def list do
    ensure_table()

    query_maps("""
    SELECT id, scope, source_id, table_name, column_name, inserted_at
    FROM phoenix_lens_protections
    ORDER BY scope, source_id NULLS FIRST, table_name NULLS FIRST, column_name
    """)
  rescue
    _ -> []
  end

  def add(attrs) when is_map(attrs) do
    with {:ok, row} <- normalize(attrs) do
      ensure_table()
      repo = repo()

      if is_nil(repo) do
        {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
      else
        repo.query!(
          """
          INSERT INTO phoenix_lens_protections (scope, source_id, table_name, column_name, inserted_at)
          VALUES ($1, $2, $3, $4, NOW())
          ON CONFLICT (scope, source_id, table_name, column_name) DO NOTHING
          """,
          [row.scope, row.source_id || "", row.table_name || "", row.column_name],
          log: false
        )

        reload()
        {:ok, row}
      end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def remove(id) do
    ensure_table()
    repo = repo()

    if is_nil(repo) do
      {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
    else
      repo.query!("DELETE FROM phoenix_lens_protections WHERE id = $1", [to_int(id)], log: false)
      reload()
      :ok
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def remove_rule(scope, source_id, table_name, column_name) do
    with {:ok, row} <-
           normalize(%{
             scope: scope,
             source_id: source_id,
             table_name: table_name,
             column_name: column_name
           }) do
      ensure_table()
      repo = repo()

      if is_nil(repo) do
        {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
      else
        repo.query!(
          """
          DELETE FROM phoenix_lens_protections
          WHERE scope = $1 AND source_id = $2 AND table_name = $3 AND column_name = $4
          """,
          [row.scope, row.source_id || "", row.table_name || "", row.column_name],
          log: false
        )

        reload()
        :ok
      end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def normalize(attrs) do
    scope = attrs[:scope] || attrs["scope"] || "global"
    scope = scope |> to_string() |> String.downcase()
    source_id = blank(attrs[:source_id] || attrs["source_id"])
    table = blank(attrs[:table_name] || attrs["table_name"] || attrs[:table])
    column = attrs[:column_name] || attrs["column_name"] || attrs[:column] || attrs["column"]

    column =
      column
      |> to_string()
      |> String.trim()
      |> String.downcase()

    cond do
      scope not in @scopes ->
        {:error, %Error{message: "scope must be global, source, or table", kind: :config}}

      not Regex.match?(~r/\A[a-z_][a-z0-9_]*\z/, column) ->
        {:error, %Error{message: "column must be a SQL identifier", kind: :config}}

      scope == "source" and is_nil(source_id) ->
        {:error, %Error{message: "source is required", kind: :config}}

      scope == "table" and (is_nil(source_id) or is_nil(table)) ->
        {:error, %Error{message: "source and table are required", kind: :config}}

      true ->
        source_id = if scope == "global", do: nil, else: down(source_id)
        table = if scope == "table", do: down(table), else: nil
        {:ok, %{scope: scope, source_id: source_id, table_name: table, column_name: column}}
    end
  end

  def ensure_table do
    case repo() do
      nil ->
        :ok

      repo ->
        repo.query!(table_sql(), [], log: false)
        :ok
    end
  rescue
    _ -> :ok
  end

  def table_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_protections (
      id bigserial PRIMARY KEY,
      scope text NOT NULL,
      source_id text NOT NULL DEFAULT '',
      table_name text NOT NULL DEFAULT '',
      column_name text NOT NULL,
      inserted_at timestamp(6) NOT NULL DEFAULT now(),
      UNIQUE (scope, source_id, table_name, column_name)
    )
    """
  end

  defp load_rules do
    ensure_table()

    Enum.reduce(list(), empty_rules(), fn row, acc ->
      col = down(row["column_name"])
      scope = row["scope"]
      source = blank(row["source_id"]) |> down()
      table = blank(row["table_name"]) |> down()

      case scope do
        "global" ->
          update_in(acc.global, &MapSet.put(&1, col))

        "source" when is_binary(source) ->
          update_in(acc.sources, fn map ->
            Map.update(map, source, MapSet.new([col]), &MapSet.put(&1, col))
          end)

        "table" when is_binary(source) and is_binary(table) ->
          update_in(acc.tables, fn map ->
            Map.update(map, {source, table}, MapSet.new([col]), &MapSet.put(&1, col))
          end)

        _ ->
          acc
      end
    end)
  end

  defp empty_rules do
    %{global: MapSet.new(), sources: %{}, tables: %{}}
  end

  defp table_names(rules, db, %{table: table} = ref) when is_binary(table) do
    source = down(ref[:source] || db)
    table = down(table)

    [
      Map.get(rules.tables, {source, table}, MapSet.new()),
      Map.get(rules.tables, {db, table}, MapSet.new()),
      Map.get(rules.tables, {"primary", table}, MapSet.new())
    ]
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp table_names(rules, db, table) when is_binary(table) do
    table_names(rules, db, %{source: db, table: table})
  end

  defp table_names(_, _, _), do: MapSet.new()

  defp query_maps(sql, params \\ []) do
    case repo() do
      nil ->
        []

      repo ->
        %{rows: rows, columns: columns} = repo.query!(sql, params, log: false)

        Enum.map(rows, fn row ->
          columns |> Enum.map(&to_string/1) |> Enum.zip(row) |> Map.new()
        end)
    end
  end

  defp repo, do: Config.get().metadata_repo

  defp blank(nil), do: nil
  defp blank(""), do: nil

  defp blank(v),
    do: to_string(v) |> String.trim() |> then(fn s -> if s == "", do: nil, else: s end)

  defp down(nil), do: nil
  defp down(v), do: v |> to_string() |> String.trim() |> String.downcase()

  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)
end
