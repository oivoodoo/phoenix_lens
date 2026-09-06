defmodule PhoenixLens.Query do
  @moduledoc false

  alias PhoenixLens.{Audit, Config, Error, Policy, Result, SQL}

  def run(sql, opts \\ []) do
    started = System.monotonic_time(:millisecond)
    config = Config.get()
    database_id = opts[:database] |> to_string_id()
    db = Config.database(database_id)
    actor = opts[:actor]
    question_id = opts[:question_id]

    with {:ok, sql} <- SQL.validate(sql),
         {:ok, db} <- require_db(db) do
      try do
        raw = execute(db, sql, config)
        duration = System.monotonic_time(:millisecond) - started
        result = apply_policy(raw, sql, config, database_id, duration)
        _ = Audit.record(sql, result, actor, database_id, question_id, nil)
        {:ok, result}
      rescue
        e ->
          duration = System.monotonic_time(:millisecond) - started
          error = Error.from_exception(e)
          _ = Audit.record(sql, nil, actor, database_id, question_id, error, duration)
          {:error, error}
      catch
        :throw, %Error{} = error ->
          duration = System.monotonic_time(:millisecond) - started
          _ = Audit.record(sql, nil, actor, database_id, question_id, error, duration)
          {:error, error}
      end
    end
  end

  defp require_db(nil) do
    {:error,
     %Error{
       message: "PhoenixLens is not configured. Set config :phoenix_lens, repo: MyApp.Repo",
       kind: :config
     }}
  end

  defp require_db(db), do: {:ok, db}

  defp execute(db, sql, config) do
    timeout = config.timeout_ms
    max_rows = config.max_rows

    cond do
      repo = db[:repo] ->
        execute_repo(repo, sql, timeout, max_rows)

      db[:url] ->
        execute_postgrex(Config.connection_name(db[:id]), sql, timeout, max_rows)

      true ->
        throw(%Error{message: "database has neither repo nor url", kind: :config})
    end
  end

  defp execute_repo(repo, sql, timeout, max_rows) do
    # Source: https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.html#query/4
    # Repo.query/3 is injected by Ecto.Adapters.SQL.
    result =
      repo.transaction(
        fn ->
          _ = repo.query!("SET LOCAL transaction_read_only = on", [], log: false)
          _ = repo.query!("SET LOCAL statement_timeout = #{timeout}", [], log: false)

          case repo.query(sql, [], timeout: timeout + 1_000, log: false) do
            {:ok, result} -> result
            {:error, err} -> repo.rollback(err)
          end
        end,
        timeout: timeout + 2_000
      )

    unwrap_tx(result, max_rows)
  end

  defp execute_postgrex(conn_name, sql, timeout, max_rows) do
    result =
      Postgrex.transaction(
        conn_name,
        fn conn ->
          {:ok, _} = Postgrex.query(conn, "SET LOCAL transaction_read_only = on", [])

          {:ok, _} =
            Postgrex.query(conn, "SET LOCAL statement_timeout = #{timeout}", [])

          case Postgrex.query(conn, sql, [], timeout: timeout + 1_000) do
            {:ok, result} -> result
            {:error, err} -> Postgrex.rollback(conn, err)
          end
        end,
        timeout: timeout + 2_000
      )

    unwrap_tx(result, max_rows)
  end

  defp unwrap_tx({:ok, %{columns: columns, rows: rows, num_rows: num_rows}}, max_rows) do
    truncate(columns || [], rows || [], num_rows || length(rows || []), max_rows)
  end

  defp unwrap_tx({:ok, %Postgrex.Result{} = result}, max_rows) do
    truncate(
      result.columns || [],
      result.rows || [],
      result.num_rows || 0,
      max_rows
    )
  end

  defp unwrap_tx({:error, %Error{} = error}, _), do: throw(error)
  defp unwrap_tx({:error, reason}, _), do: raise(unwrap_reason(reason))
  defp unwrap_tx({:rollback, reason}, _), do: raise(unwrap_reason(reason))

  defp unwrap_reason(%{__exception__: true} = e), do: e
  defp unwrap_reason(other), do: %Error{message: inspect(other), kind: :sql}

  defp truncate(columns, rows, num_rows, max_rows) do
    truncated = length(rows) > max_rows
    rows = Enum.take(rows, max_rows)

    %{
      columns: Enum.map(columns, &to_string/1),
      rows: rows,
      num_rows: min(num_rows, length(rows)),
      truncated: truncated
    }
  end

  defp apply_policy(raw, sql, config, database_id, duration) do
    protected = Policy.protected_set(config, database_id)
    origins = SQL.column_origins(sql, raw.columns)
    {_cols, rows, masked} = Policy.apply(origins, raw.rows, protected, sql)

    %Result{
      columns: raw.columns,
      rows: rows,
      masked_columns: masked,
      truncated: raw.truncated,
      num_rows: length(rows),
      duration_ms: max(duration, 0),
      database_id: database_id,
      sql: sql
    }
  end

  defp to_string_id(nil), do: "primary"
  defp to_string_id(id), do: to_string(id)
end
