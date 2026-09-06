defmodule PhoenixLens.DuckDB do
  @moduledoc false

  alias PhoenixLens.{Config, Error, Settings}

  @host_alias "repo"

  def available? do
    Code.ensure_loaded?(Duckdbex) and function_exported?(Duckdbex, :open, 0)
  end

  def missing_message do
    "DuckDB engine requires {:duckdbex, \"~> 0.4\"} in your mix.exs, then mix deps.get"
  end

  def host_alias, do: @host_alias

  def open_memory do
    unless available?() do
      {:error, %Error{message: missing_message(), kind: :config}}
    else
      with {:ok, db} <- Duckdbex.open(),
           {:ok, conn} <- Duckdbex.connection(db) do
        {:ok, %{db: db, conn: conn}}
      else
        {:error, reason} -> {:error, %Error{message: format_reason(reason), kind: :config}}
      end
    end
  end

  def query(%{conn: conn}, sql) when is_binary(sql), do: query(conn, sql)

  def query(conn, sql) when is_binary(sql) do
    case Duckdbex.query(conn, sql) do
      {:ok, result} ->
        columns = Duckdbex.columns(result)
        rows = Duckdbex.fetch_all(result)
        _ = Duckdbex.release(result)

        cond do
          match?({:error, _}, columns) ->
            {:error, %Error{message: format_reason(elem(columns, 1)), kind: :sql}}

          match?({:error, _}, rows) ->
            {:error, %Error{message: format_reason(elem(rows, 1)), kind: :sql}}

          true ->
            {:ok,
             %{
               columns: Enum.map(columns, &to_string/1),
               rows: rows || [],
               num_rows: length(rows || [])
             }}
        end

      {:error, reason} ->
        {:error, %Error{message: format_reason(reason), kind: :sql}}
    end
  end

  def exec(conn, sql) do
    case query(conn, sql) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  def attach_all(conn, sources) when is_list(sources) do
    Enum.map(sources, fn source ->
      case attach_one(conn, source) do
        :ok ->
          maybe_clear_error(source)
          %{source | error: nil, ok?: true}

        {:error, %Error{} = error} ->
          maybe_record_error(source, error.message)
          %{source | error: error.message, ok?: false}
      end
    end)
  end

  def attach_one(conn, source) do
    kind = source.kind
    _ = maybe_install(conn, kind, source.dsn)

    case exec(conn, attach_sql(source)) do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  def alias_host_tables(conn, repo_alias, reserved) when is_binary(repo_alias) do
    sql = """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_catalog = #{sql_string(repo_alias)}
      AND table_schema IN ('public', 'main')
      AND table_name NOT LIKE 'phoenix_lens_%'
      AND table_name <> 'schema_migrations'
    """

    case query(conn, sql) do
      {:ok, %{rows: rows}} ->
        Enum.each(rows, fn
          [name] when is_binary(name) ->
            if name not in reserved and valid_ident?(name) do
              _ =
                exec(
                  conn,
                  "CREATE OR REPLACE VIEW #{quote_ident(name)} AS SELECT * FROM #{quote_ident(repo_alias)}.#{quote_ident(name)}"
                )
            end

          _ ->
            :ok
        end)

        :ok

      {:error, _} ->
        :ok
    end
  end

  def tables(conn) do
    sql = """
    SELECT database_name, schema_name, table_name, column_name, data_type
    FROM duckdb_columns()
    WHERE NOT internal
      AND schema_name NOT IN ('information_schema', 'pg_catalog')
      AND table_name NOT LIKE 'phoenix_lens_%'
      AND table_name <> 'schema_migrations'
    ORDER BY database_name, schema_name, table_name, column_index
    """

    case query(conn, sql) do
      {:ok, %{rows: rows}} ->
        rows
        |> Enum.group_by(fn [db, schema, table, _, _] -> {db, schema, table} end)
        |> Enum.map(fn {{db, schema, table}, cols} ->
          %{
            name: display_name(db, schema, table),
            database: db,
            schema: schema,
            table: table,
            columns:
              Enum.map(cols, fn [_, _, _, name, type] ->
                %{name: to_string(name), type: to_string(type)}
              end)
          }
        end)
        |> Enum.sort_by(&catalog_rank/1)
        |> Enum.uniq_by(& &1.name)
        |> Enum.sort_by(& &1.name)

      {:error, _} ->
        []
    end
  end

  def configured_sources do
    host = host_source()
    extras = config_database_sources()
    user = user_sources()

    used = MapSet.new(user, & &1.alias)

    [host]
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(Enum.reject(extras, &MapSet.member?(used, &1.alias)))
    |> Kernel.++(user)
  end

  def host_source do
    db = Config.database("primary")
    dsn = Config.postgres_dsn(db)

    if is_binary(dsn) and dsn != "" do
      %{
        id: nil,
        alias: @host_alias,
        kind: "postgres",
        dsn: dsn,
        builtin?: true,
        label: "Host Repo",
        error: nil,
        ok?: nil
      }
    end
  end

  defp config_database_sources do
    Config.get().databases
    |> Enum.reject(fn {id, _} -> id in ["primary", @host_alias] end)
    |> Enum.flat_map(fn {id, db} ->
      dsn = Config.postgres_dsn(db)
      alias_ = sanitize_alias(id)

      if is_binary(dsn) and dsn != "" and alias_ do
        [
          %{
            id: nil,
            alias: alias_,
            kind: "postgres",
            dsn: dsn,
            builtin?: true,
            label: db[:name] || alias_,
            error: nil,
            ok?: nil
          }
        ]
      else
        []
      end
    end)
  end

  defp user_sources do
    Enum.map(Settings.sources(), fn source ->
      %{
        id: source["id"],
        alias: source["alias"],
        kind: source["kind"],
        dsn: source["dsn"],
        builtin?: false,
        label: source["alias"],
        error: source["error"],
        ok?: nil
      }
    end)
  end

  defp attach_sql(%{kind: kind, alias: alias_, dsn: dsn}) when kind in ["postgres", "sqlite"] do
    "ATTACH #{sql_string(dsn)} AS #{quote_ident(alias_)} (TYPE #{kind}, READ_ONLY)"
  end

  defp attach_sql(%{kind: "duckdb", alias: alias_, dsn: dsn}) do
    "ATTACH #{sql_string(dsn)} AS #{quote_ident(alias_)} (READ_ONLY)"
  end

  defp attach_sql(%{kind: kind, alias: alias_, dsn: dsn})
       when kind in ["parquet", "csv", "json"] do
    reader =
      case kind do
        "parquet" -> "read_parquet"
        "csv" -> "read_csv_auto"
        "json" -> "read_json_auto"
      end

    "CREATE OR REPLACE VIEW #{quote_ident(alias_)} AS SELECT * FROM #{reader}(#{sql_string(dsn)})"
  end

  defp maybe_install(conn, kind, dsn) do
    extensions =
      case kind do
        "postgres" -> ["postgres"]
        "sqlite" -> ["sqlite"]
        _ -> []
      end

    extensions =
      if remote_path?(dsn) do
        ["httpfs" | extensions]
      else
        extensions
      end

    Enum.each(Enum.uniq(extensions), fn ext ->
      _ = exec(conn, "INSTALL #{ext}")
      _ = exec(conn, "LOAD #{ext}")
    end)
  end

  defp remote_path?(dsn) when is_binary(dsn) do
    String.starts_with?(dsn, ["http://", "https://", "s3://", "gs://", "azure://"])
  end

  defp remote_path?(_), do: false

  defp catalog_rank(%{database: db}) do
    cond do
      db in ["memory", "temp"] -> 0
      db == @host_alias -> 1
      true -> 2
    end
  end

  defp display_name(db, schema, table) do
    cond do
      db in ["memory", "temp"] and schema in ["main", "public"] -> table
      db == @host_alias and schema in ["main", "public"] -> table
      schema in ["main", "public"] -> "#{db}.#{table}"
      true -> "#{db}.#{schema}.#{table}"
    end
  end

  defp sanitize_alias(id) do
    alias_ =
      id
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]/, "_")
      |> String.trim("_")

    if Regex.match?(~r/\A[a-z][a-z0-9_]{0,62}\z/, alias_), do: alias_
  end

  defp valid_ident?(name) when is_binary(name) do
    Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, name)
  end

  defp valid_ident?(_), do: false

  def quote_ident(name) do
    "\"" <> String.replace(to_string(name), "\"", "\"\"") <> "\""
  end

  def sql_string(value) do
    "'" <> String.replace(to_string(value), "'", "''") <> "'"
  end

  defp maybe_record_error(%{id: id}, message) when is_integer(id) do
    Settings.record_source_error(id, message)
  end

  defp maybe_record_error(_, _), do: :ok

  defp maybe_clear_error(%{id: id}) when is_integer(id) do
    Settings.clear_source_error(id)
  end

  defp maybe_clear_error(_), do: :ok

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
