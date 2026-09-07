defmodule PhoenixLens.Alerts.Runner do
  @moduledoc false

  alias PhoenixLens.{Alerts, Integrations, Query, Result}
  alias PhoenixLens.Alerts.Mailer

  def run_due(now \\ DateTime.utc_now()) do
    Alerts.enabled()
    |> Enum.filter(&Alerts.due?(&1, now))
    |> Enum.map(&run_one(&1, force: false))
  end

  def run_one(id_or_alert, opts \\ [])

  def run_one(id, opts) when is_integer(id) or is_binary(id) do
    case Alerts.get(id) do
      {:ok, alert} -> run_one(alert, opts)
      other -> other
    end
  end

  def run_one(alert, opts) when is_map(alert) do
    force? = opts[:force] == true
    actor = opts[:actor] || "alert:#{alert["id"]}"

    case Query.run(alert["sql"],
           database: alert["database_id"],
           actor: actor,
           question_id: alert["question_id"]
         ) do
      {:ok, result} ->
        if force? or triggered?(alert, result) do
          case deliver(alert, result) do
            :ok ->
              Alerts.record_run(alert["id"],
                fired: true,
                status: "sent",
                error: nil,
                disable: alert["once"] == true
              )

              {:ok, %{fired: true, num_rows: result.num_rows}}

            {:error, message} ->
              Alerts.record_run(alert["id"], fired: false, status: "error", error: message)
              {:error, message}
          end
        else
          Alerts.record_run(alert["id"], fired: false, status: "quiet", error: nil)
          {:ok, %{fired: false, num_rows: result.num_rows}}
        end

      {:error, error} ->
        Alerts.record_run(alert["id"], fired: false, status: "error", error: error.message)
        {:error, error.message}
    end
  end

  def triggered?(alert, %Result{} = result) do
    case alert["condition"] do
      "rows" -> result.num_rows > 0
      "no_rows" -> result.num_rows == 0
      "above" -> compare(result, alert["threshold"], :>=)
      "below" -> compare(result, alert["threshold"], :<=)
      _ -> false
    end
  end

  def numeric_value(%Result{rows: [row | _], columns: columns}) do
    Enum.zip(columns, row)
    |> Enum.find_value(fn {_col, cell} ->
      case cell do
        :redacted -> nil
        n when is_number(n) -> n * 1.0
        n when is_struct(n, Decimal) -> Decimal.to_float(n)
        bin when is_binary(bin) -> Alerts.parse_number(bin)
        _ -> nil
      end
    end)
  end

  def numeric_value(_), do: nil

  defp compare(result, threshold, op) do
    with value when is_number(value) <- numeric_value(result),
         limit when is_number(limit) <- Alerts.parse_number(threshold) do
      case op do
        :>= -> value >= limit
        :<= -> value <= limit
      end
    else
      _ -> false
    end
  end

  defp deliver(alert, result) do
    emails = Alerts.parse_emails(alert["emails"])
    hook_ids = Alerts.parse_webhook_ids(alert["webhook_ids"])
    payload = payload(alert, result)

    email_results =
      Enum.map(emails, fn to ->
        case Integrations.email() do
          nil ->
            {:error, "email is not configured"}

          row ->
            Mailer.send(row["config"] || %{}, to, subject(alert), email_body(alert, result))
        end
      end)

    hook_results =
      Enum.map(hook_ids, fn id ->
        case Integrations.get(id) do
          {:ok, %{"kind" => "webhook"} = hook} -> post_webhook(hook, payload)
          {:ok, _} -> {:error, "integration #{id} is not a webhook"}
          {:error, error} -> {:error, error.message}
        end
      end)

    errors =
      (email_results ++ hook_results)
      |> Enum.flat_map(fn
        :ok -> []
        {:error, msg} -> [msg]
      end)

    cond do
      emails == [] and hook_ids == [] -> {:error, "no destinations"}
      errors == [] -> :ok
      true -> {:error, Enum.join(errors, "; ")}
    end
  end

  def payload(alert, %Result{} = result) do
    %{
      "type" => "alert",
      "alert_id" => alert["id"],
      "alert_condition" => alert["condition"],
      "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "data" => %{
        "type" => "question",
        "question_id" => alert["question_id"],
        "question_name" => alert["question_name"],
        "raw_data" => %{
          "cols" => result.columns,
          "rows" => Enum.map(result.rows, fn row -> Enum.map(row, &json_cell/1) end)
        },
        "num_rows" => result.num_rows,
        "masked_columns" => result.masked_columns
      }
    }
  end

  defp post_webhook(hook, payload) do
    cfg = hook["config"] || %{}
    url = cfg["url"]

    if not is_binary(url) or url == "" do
      {:error, "webhook URL is missing"}
    else
      headers = [{~c"content-type", ~c"application/json"}] ++ auth_headers(cfg)
      body = Jason.encode!(payload)

      _ = Application.ensure_all_started(:inets)
      _ = Application.ensure_all_started(:ssl)

      request = {String.to_charlist(url), headers, ~c"application/json", body}

      http_opts = [timeout: 10_000, connect_timeout: 5_000]

      case :httpc.request(:post, request, http_opts, []) do
        {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
          :ok

        {:ok, {{_, status, _}, _, resp}} ->
          {:error, "webhook HTTP #{status}: #{resp |> to_string() |> String.slice(0, 180)}"}

        {:error, reason} ->
          {:error, "webhook failed: #{inspect(reason)}"}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp auth_headers(%{"auth" => "bearer", "token" => token})
       when is_binary(token) and token != "" do
    [{~c"authorization", String.to_charlist("Bearer #{token}")}]
  end

  defp auth_headers(%{"auth" => "header", "token" => token, "header" => header})
       when is_binary(token) and token != "" do
    name = header |> to_string() |> String.downcase() |> String.to_charlist()
    [{name, String.to_charlist(token)}]
  end

  defp auth_headers(_), do: []

  defp subject(alert) do
    "Lens alert: #{alert["question_name"] || "question #{alert["question_id"]}"}"
  end

  defp email_body(alert, result) do
    header = Enum.join(result.columns, " | ")

    rows =
      result.rows
      |> Enum.take(25)
      |> Enum.map(fn row ->
        row |> Enum.map(&Result.display_cell/1) |> Enum.join(" | ")
      end)
      |> Enum.join("\n")

    """
    Alert on #{alert["question_name"]} (#{alert["condition"]}).
    Rows: #{result.num_rows}

    #{header}
    #{rows}

    Masked columns stay [redacted].
    """
    |> String.trim()
  end

  defp json_cell(:redacted), do: Result.redacted_label()
  defp json_cell(nil), do: nil
  defp json_cell(value) when is_number(value) or is_boolean(value), do: value
  defp json_cell(value) when is_struct(value, Decimal), do: Decimal.to_float(value)
  defp json_cell(value), do: Result.display_cell(value)
end
