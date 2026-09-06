defmodule PhoenixLens.Audit do
  @moduledoc false

  alias PhoenixLens.{Config, Redactor, Settings}

  @default_per_page 25

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
        {:ok, _} ->
          _ = purge_expired()
          :ok

        {:error, _} ->
          :ok
      end
    end
  rescue
    _ -> :ok
  end

  def page(page \\ 1, per_page \\ @default_per_page) do
    _ = purge_expired()
    per_page = per_page |> to_int() |> max(1) |> min(100)
    total = count()
    pages = max(ceil(total / per_page), 1)
    page = page |> to_int() |> max(1) |> min(pages)
    offset = (page - 1) * per_page
    entries = recent(per_page, offset)

    %{
      entries: entries,
      page: page,
      pages: pages,
      total: total,
      per_page: per_page,
      from: if(total == 0, do: 0, else: offset + 1),
      to: min(offset + length(entries), total)
    }
  end

  def recent(limit \\ 100, offset \\ 0) do
    repo = Config.get().metadata_repo
    limit = limit |> to_int() |> max(1) |> min(500)
    offset = offset |> to_int() |> max(0)

    if is_nil(repo) do
      []
    else
      case repo.query(
             """
             SELECT id, actor, database_id, question_id, sql_redacted, query_hash,
                    row_count, duration_ms, masked_columns, truncated, error, inserted_at
             FROM phoenix_lens_audit
             ORDER BY inserted_at DESC
             LIMIT $1 OFFSET $2
             """,
             [limit, offset],
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

  def count do
    repo = Config.get().metadata_repo

    if is_nil(repo) do
      0
    else
      case repo.query("SELECT count(*) FROM phoenix_lens_audit", [], log: false) do
        {:ok, %{rows: [[n]]}} -> n
        _ -> 0
      end
    end
  rescue
    _ -> 0
  end

  def purge_expired do
    days = Settings.audit_retention_days()
    repo = Config.get().metadata_repo

    cond do
      is_nil(repo) ->
        :ok

      days in [nil, 0] ->
        :ok

      true ->
        repo.query(
          "DELETE FROM phoenix_lens_audit WHERE inserted_at < NOW() - ($1 * INTERVAL '1 day')",
          [days],
          log: false
        )

        :ok
    end
  rescue
    _ -> :ok
  end

  def format_when(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  def format_when(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  def format_when(other) when is_binary(other) do
    other
    |> String.replace("T", " ")
    |> String.replace(~r/\.\d+.*$/, "")
    |> String.slice(0, 16)
  end

  def format_when(other), do: to_string(other)

  defp row_to_map(columns, row) do
    columns
    |> Enum.map(&to_string/1)
    |> Enum.zip(row)
    |> Map.new()
  end

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> 1
    end
  end

  defp to_int(_), do: 1
end
