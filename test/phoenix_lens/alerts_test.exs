defmodule PhoenixLens.AlertsTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.{Alerts, Result}
  alias PhoenixLens.Alerts.Runner

  defp result(rows) do
    cols = ["status", "count"]
    %Result{columns: cols, rows: rows, masked_columns: [], num_rows: length(rows)}
  end

  test "rows condition fires only when there are rows" do
    assert Runner.triggered?(%{"condition" => "rows"}, result([["paid", 3]]))
    refute Runner.triggered?(%{"condition" => "rows"}, result([]))
  end

  test "no_rows condition fires when empty" do
    assert Runner.triggered?(%{"condition" => "no_rows"}, result([]))
    refute Runner.triggered?(%{"condition" => "no_rows"}, result([["paid", 1]]))
  end

  test "above/below use the first numeric cell" do
    r = result([["paid", 12]])
    assert Runner.triggered?(%{"condition" => "above", "threshold" => "10"}, r)
    refute Runner.triggered?(%{"condition" => "above", "threshold" => "20"}, r)
    assert Runner.triggered?(%{"condition" => "below", "threshold" => "20"}, r)
    refute Runner.triggered?(%{"condition" => "below", "threshold" => "10"}, r)
  end

  test "redacted cells are not used as the goal value" do
    r = %Result{
      columns: ["email", "count"],
      rows: [[:redacted, 5]],
      masked_columns: ["email"],
      num_rows: 1
    }

    assert Runner.numeric_value(r) == 5.0
  end

  test "due? is true when never run" do
    assert Alerts.due?(%{"last_run_at" => nil, "schedule" => "1h"})
  end

  test "due? respects schedule window" do
    now = ~U[2026-09-07 12:00:00Z]
    recent = DateTime.add(now, -10, :minute)
    stale = DateTime.add(now, -2, :hour)

    refute Alerts.due?(%{"last_run_at" => recent, "schedule" => "1h"}, now)
    assert Alerts.due?(%{"last_run_at" => stale, "schedule" => "1h"}, now)
  end

  test "parse_emails and webhook ids" do
    assert Alerts.parse_emails("a@x.com, b@y.com") == ["a@x.com", "b@y.com"]
    refute Alerts.valid_email?("not-an-email")
    assert Alerts.parse_webhook_ids("1, 2, x") == [1, 2]
  end

  test "webhook payload keeps masked cells as [redacted]" do
    alert = %{"id" => 9, "question_id" => 5, "question_name" => "Users", "condition" => "rows"}

    result = %Result{
      columns: ["id", "email"],
      rows: [[1, :redacted]],
      masked_columns: ["email"],
      num_rows: 1
    }

    payload = Runner.payload(alert, result)
    assert payload["type"] == "alert"
    assert payload["data"]["raw_data"]["rows"] == [[1, "[redacted]"]]
  end
end
