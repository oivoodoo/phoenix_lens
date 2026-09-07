defmodule PhoenixLens.Alerts do
  @moduledoc """
  Saved-question alerts. Checked on a schedule; sent by email and/or webhook.
  """

  alias PhoenixLens.{Config, Error, Questions}

  @conditions ~w(rows no_rows above below)
  @schedules ~w(1m 5m 15m 1h 6h 1d)

  def conditions, do: @conditions
  def schedules, do: @schedules

  def table_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_alerts (
      id bigserial PRIMARY KEY,
      question_id bigint NOT NULL REFERENCES phoenix_lens_questions(id) ON DELETE CASCADE,
      condition text NOT NULL DEFAULT 'rows',
      threshold text,
      schedule text NOT NULL DEFAULT '1h',
      once boolean NOT NULL DEFAULT false,
      enabled boolean NOT NULL DEFAULT true,
      emails text NOT NULL DEFAULT '',
      webhook_ids text NOT NULL DEFAULT '',
      last_run_at timestamp(6),
      last_fired_at timestamp(6),
      last_status text,
      last_error text,
      inserted_at timestamp(6) NOT NULL DEFAULT now(),
      updated_at timestamp(6) NOT NULL DEFAULT now()
    )
    """
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

  def list do
    ensure_table()
    query_maps(select_sql() <> " ORDER BY a.id DESC")
  rescue
    _ -> []
  end

  def list_for_question(question_id) do
    ensure_table()

    query_maps(
      select_sql() <> " WHERE a.question_id = $1 ORDER BY a.id DESC",
      [to_int(question_id)]
    )
  rescue
    _ -> []
  end

  def enabled do
    ensure_table()
    query_maps(select_sql() <> " WHERE a.enabled = TRUE ORDER BY a.id")
  rescue
    _ -> []
  end

  def get(id) do
    ensure_table()

    case query_maps(select_sql() <> " WHERE a.id = $1", [to_int(id)]) do
      [row] -> {:ok, row}
      [] -> {:error, %Error{message: "alert not found", kind: :config}}
    end
  end

  def save(attrs) when is_map(attrs) do
    with {:ok, data} <- normalize(attrs) do
      ensure_table()

      case repo() do
        nil ->
          {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}

        repo ->
          cond do
            data.id ->
              repo.query!(
                """
                UPDATE phoenix_lens_alerts
                SET question_id = $2, condition = $3, threshold = $4, schedule = $5,
                    once = $6, enabled = $7, emails = $8, webhook_ids = $9, updated_at = NOW()
                WHERE id = $1
                """,
                [
                  data.id,
                  data.question_id,
                  data.condition,
                  data.threshold,
                  data.schedule,
                  data.once,
                  data.enabled,
                  data.emails,
                  data.webhook_ids
                ],
                log: false
              )

              get(data.id)

            true ->
              %{rows: [[id]]} =
                repo.query!(
                  """
                  INSERT INTO phoenix_lens_alerts
                    (question_id, condition, threshold, schedule, once, enabled, emails, webhook_ids, inserted_at, updated_at)
                  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())
                  RETURNING id
                  """,
                  [
                    data.question_id,
                    data.condition,
                    data.threshold,
                    data.schedule,
                    data.once,
                    data.enabled,
                    data.emails,
                    data.webhook_ids
                  ],
                  log: false
                )

              get(id)
          end
      end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def delete(id) do
    ensure_table()

    case repo() do
      nil ->
        {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}

      repo ->
        repo.query!("DELETE FROM phoenix_lens_alerts WHERE id = $1", [to_int(id)], log: false)
        :ok
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def record_run(id, attrs) when is_map(attrs) do
    ensure_table()
    repo = repo()

    if repo do
      repo.query!(
        """
        UPDATE phoenix_lens_alerts
        SET last_run_at = NOW(),
            last_fired_at = CASE WHEN $2 THEN NOW() ELSE last_fired_at END,
            last_status = $3,
            last_error = $4,
            enabled = CASE WHEN $5 THEN FALSE ELSE enabled END,
            updated_at = NOW()
        WHERE id = $1
        """,
        [
          to_int(id),
          attrs[:fired] == true,
          attrs[:status],
          attrs[:error],
          attrs[:disable] == true
        ],
        log: false
      )
    end

    :ok
  rescue
    _ -> :ok
  end

  def interval_ms("1m"), do: 60_000
  def interval_ms("5m"), do: 5 * 60_000
  def interval_ms("15m"), do: 15 * 60_000
  def interval_ms("1h"), do: 60 * 60_000
  def interval_ms("6h"), do: 6 * 60 * 60_000
  def interval_ms("1d"), do: 24 * 60 * 60_000
  def interval_ms(_), do: 60 * 60_000

  def due?(alert, now \\ DateTime.utc_now()) do
    case parse_time(alert["last_run_at"]) do
      nil ->
        true

      last ->
        DateTime.diff(now, last, :millisecond) >= interval_ms(alert["schedule"])
    end
  end

  def parse_emails(value) when is_binary(value) do
    value
    |> String.split([",", ";", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&valid_email?/1)
    |> Enum.uniq()
  end

  def parse_emails(list) when is_list(list), do: list |> Enum.map(&to_string/1) |> parse_emails()
  def parse_emails(_), do: []

  def parse_webhook_ids(value) when is_binary(value) do
    value
    |> String.split([",", " "], trim: true)
    |> Enum.flat_map(fn part ->
      case Integer.parse(part) do
        {int, ""} -> [int]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  def parse_webhook_ids(list) when is_list(list) do
    Enum.flat_map(list, fn
      n when is_integer(n) -> [n]
      n -> parse_webhook_ids(to_string(n))
    end)
  end

  def parse_webhook_ids(_), do: []

  defp normalize(attrs) do
    question_id = attrs[:question_id] || attrs["question_id"]
    condition = attrs[:condition] || attrs["condition"] || "rows"
    condition = condition |> to_string() |> String.downcase()
    schedule = attrs[:schedule] || attrs["schedule"] || "1h"
    schedule = schedule |> to_string() |> String.downcase()
    threshold = blank(attrs[:threshold] || attrs["threshold"])
    emails = parse_emails(attrs[:emails] || attrs["emails"] || "")
    webhook_ids = parse_webhook_ids(attrs[:webhook_ids] || attrs["webhook_ids"] || [])
    once = truthy?(attrs[:once] || attrs["once"], false)
    enabled = truthy?(attrs[:enabled] || attrs["enabled"], true)
    id = attrs[:id] || attrs["id"]

    cond do
      is_nil(question_id) ->
        {:error, %Error{message: "question is required", kind: :config}}

      condition not in @conditions ->
        {:error,
         %Error{message: "condition must be rows, no_rows, above, or below", kind: :config}}

      schedule not in @schedules ->
        {:error, %Error{message: "invalid schedule", kind: :config}}

      condition in ["above", "below"] and (is_nil(threshold) or parse_number(threshold) == nil) ->
        {:error, %Error{message: "threshold is required for goal alerts", kind: :config}}

      emails == [] and webhook_ids == [] ->
        {:error, %Error{message: "add an email or webhook destination", kind: :config}}

      match?({:error, _}, Questions.get(question_id)) ->
        {:error, %Error{message: "question not found", kind: :sql}}

      true ->
        {:ok,
         %{
           id: id && to_int(id),
           question_id: to_int(question_id),
           condition: condition,
           threshold: threshold && to_string(threshold),
           schedule: schedule,
           once: once,
           enabled: enabled,
           emails: Enum.join(emails, ","),
           webhook_ids: Enum.join(webhook_ids, ",")
         }}
    end
  end

  def parse_number(nil), do: nil
  def parse_number(n) when is_number(n), do: n * 1.0

  def parse_number(n) when is_binary(n) do
    case Float.parse(String.trim(n)) do
      {f, _} -> f
      :error -> nil
    end
  end

  def parse_number(_), do: nil

  def valid_email?(addr) when is_binary(addr) do
    Regex.match?(~r/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, addr) and String.length(addr) < 200
  end

  def valid_email?(_), do: false

  defp select_sql do
    """
    SELECT a.id, a.question_id, a.condition, a.threshold, a.schedule, a.once, a.enabled,
           a.emails, a.webhook_ids, a.last_run_at, a.last_fired_at, a.last_status, a.last_error,
           a.inserted_at, a.updated_at, q.name AS question_name, q.sql, q.database_id, q.viz
    FROM phoenix_lens_alerts a
    JOIN phoenix_lens_questions q ON q.id = a.question_id
    """
  end

  defp parse_time(%DateTime{} = dt), do: dt
  defp parse_time(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  defp parse_time({{y, m, d}, {h, min, s, _us}}) do
    case DateTime.new(Date.new!(y, m, d), Time.new!(h, min, s)) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp parse_time(_), do: nil

  defp truthy?(val, default) do
    case val do
      true -> true
      false -> false
      "true" -> true
      "on" -> true
      "1" -> true
      "false" -> false
      "off" -> false
      "0" -> false
      _ -> default
    end
  end

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(v), do: to_string(v)

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
  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)
end
