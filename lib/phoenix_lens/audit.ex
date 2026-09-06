defmodule PhoenixLens.Audit do
  @moduledoc false

  alias PhoenixLens.{Config, Redactor}

  def record(sql, result, actor, database_id, question_id, error, duration_ms \\ nil) do
    repo = Config.get().metadata_repo

    if is_nil(repo) do
      :ok
    else
      sql_redacted = Redactor.sql(sql)
      duration = duration_ms || (result && result.duration_ms) || 0

      params = [
        Redactor.actor(actor),
        to_string(database_id || "primary"),
        question_id,
        sql_redacted,
        Redactor.hash(sql || ""),
        result && result.num_rows,
        duration,
        (result && result.masked_columns) || [],
        (result && result.truncated) || false,
        error && error.message
      ]

      sql = """
      INSERT INTO phoenix_lens_audit
        (actor, database_id, question_id, sql_redacted, query_hash,
         row_count, duration_ms, masked_columns, truncated, error, inserted_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
      """

      case repo.query(sql, params, log: false) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  rescue
    _ -> :ok
  end

  def recent(limit \\ 100) do
    repo = Config.get().metadata_repo

    if is_nil(repo) do
      []
    else
      case repo.query(
             """
             SELECT id, actor, database_id, question_id, sql_redacted, query_hash,
                    row_count, duration_ms, masked_columns, truncated, error, inserted_at
             FROM phoenix_lens_audit
             ORDER BY inserted_at DESC
             LIMIT $1
             """,
             [limit],
             log: false
           ) do
        {:ok, %{rows: rows, columns: columns}} ->
          Enum.map(rows, &row_to_map(columns, &1))

        _ ->
          []
      end
    end
  rescue
    _ -> []
  end

  defp row_to_map(columns, row) do
    columns
    |> Enum.map(&to_string/1)
    |> Enum.zip(row)
    |> Map.new()
  end
end
