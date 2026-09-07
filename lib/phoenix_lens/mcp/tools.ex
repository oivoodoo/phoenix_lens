defmodule PhoenixLens.MCP.Tools do
  @moduledoc false

  alias PhoenixLens.{
    Alerts,
    Audit,
    Catalog,
    Dashboards,
    DuckDB,
    Export,
    Integrations,
    Notebook,
    Protection,
    Query,
    Questions,
    Result,
    Settings
  }

  def list do
    Enum.map(defs(), fn {name, meta, _fun} ->
      %{
        "name" => name,
        "description" => meta.description,
        "inputSchema" => meta.schema
      }
    end)
  end

  def call(name, args, ctx) when is_binary(name) do
    args = stringify_keys(args || %{})

    case Enum.find(defs(), fn {n, _, _} -> n == name end) do
      {_, _, fun} ->
        try do
          case fun.(args, ctx) do
            {:ok, value} -> {:ok, value}
            {:error, %PhoenixLens.Error{} = error} -> {:error, error.message}
            {:error, message} when is_binary(message) -> {:error, message}
            other -> {:ok, other}
          end
        rescue
          e -> {:error, Exception.message(e)}
        end

      nil ->
        {:error, "unknown tool #{name}"}
    end
  end

  defp defs do
    [
      tool(
        "list_tables",
        "List catalog tables and whether each field is protected.",
        %{},
        fn _args, _ctx ->
          {:ok, Enum.map(Catalog.browse(), &table_json/1)}
        end
      ),
      tool(
        "describe_table",
        "Describe one catalog table: fields, types, and protection flags.",
        object(%{"table" => string("Table name, for example users or repo.orders")}, ["table"]),
        fn args, _ctx ->
          name = down(args["table"])

          case Enum.find(Catalog.browse(), fn t -> String.downcase(t.source) == name end) do
            nil -> {:error, "table not found"}
            table -> {:ok, table_json(table)}
          end
        end
      ),
      tool(
        "run_sql",
        "Run a read-only SELECT/WITH (or EXPLAIN) through the current query engine. Field policy masks protected cells as [redacted].",
        object(
          %{
            "sql" => string("SQL statement"),
            "database_id" => string("Configured database id (default primary)"),
            "question_id" => integer("Saved question id to attribute in the audit log")
          },
          ["sql"]
        ),
        fn args, ctx ->
          opts = [
            actor: ctx.actor,
            database: args["database_id"] || "primary",
            question_id: args["question_id"]
          ]

          case Query.run(args["sql"], opts) do
            {:ok, result} -> {:ok, result_json(result)}
            {:error, error} -> {:error, error.message}
          end
        end
      ),
      tool(
        "compile_notebook",
        "Compile a notebook (table, filters, metrics, grouping) into SQL without running it.",
        object(%{
          "table" => string("Table name"),
          "filters" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "column" => string("Column"),
                "op" => string("One of = != > < >= <= contains is_null not_null"),
                "value" => %{"description" => "Comparison value"}
              }
            }
          },
          "aggregations" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "fun" => string("count, sum, avg, min, or max"),
                "column" => string("Column for sum/avg/min/max")
              }
            }
          },
          "breakouts" => %{"type" => "array", "items" => %{"type" => "string"}},
          "sorts" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "column" => string("Column"),
                "dir" => string("asc or desc")
              }
            }
          },
          "limit" => integer("Max rows (1–10000)")
        }),
        fn args, _ctx ->
          nb = Notebook.from_attrs(args)

          case Notebook.to_sql(nb) do
            {:ok, sql} -> {:ok, %{"sql" => sql}}
            {:error, error} -> {:error, error.message}
          end
        end
      ),
      tool("list_questions", "List saved questions.", %{}, fn _args, _ctx ->
        {:ok, Questions.list()}
      end),
      tool(
        "get_question",
        "Load one saved question.",
        object(%{"id" => integer("Question id")}, ["id"]),
        fn args, _ctx -> Questions.get(args["id"]) end
      ),
      tool(
        "save_question",
        "Create or update a saved question. Pass id to update.",
        object(
          %{
            "id" => integer("Existing question id"),
            "name" => string("Question name"),
            "sql" => string("SQL"),
            "viz" => string("table, number, bar, or line"),
            "database_id" => string("Database id")
          },
          []
        ),
        fn args, _ctx ->
          Questions.save(%{
            id: args["id"],
            name: args["name"],
            sql: args["sql"],
            viz: args["viz"],
            database_id: args["database_id"]
          })
        end
      ),
      tool(
        "delete_question",
        "Delete a saved question.",
        object(%{"id" => integer("Question id")}, ["id"]),
        fn args, _ctx ->
          Questions.delete(args["id"])
          {:ok, %{"deleted" => true, "id" => args["id"]}}
        end
      ),
      tool(
        "export_csv",
        "Run SQL (or a saved question) and return masked CSV text.",
        object(%{
          "sql" => string("SQL to run"),
          "question_id" => integer("Saved question id"),
          "database_id" => string("Database id")
        }),
        fn args, ctx ->
          with {:ok, sql, db, qid} <- sql_from_args(args),
               {:ok, result} <-
                 Query.run(sql, actor: ctx.actor, database: db, question_id: qid) do
            {:ok, %{"format" => "csv", "csv" => Export.csv(result)}}
          end
        end
      ),
      tool(
        "export_json",
        "Run SQL (or a saved question) and return masked JSON rows.",
        object(%{
          "sql" => string("SQL to run"),
          "question_id" => integer("Saved question id"),
          "database_id" => string("Database id")
        }),
        fn args, ctx ->
          with {:ok, sql, db, qid} <- sql_from_args(args),
               {:ok, result} <-
                 Query.run(sql, actor: ctx.actor, database: db, question_id: qid) do
            {:ok, result_json(result)}
          end
        end
      ),
      tool("list_dashboards", "List dashboards.", %{}, fn _args, _ctx ->
        {:ok, Dashboards.list()}
      end),
      tool(
        "get_dashboard",
        "Load a dashboard and its cards.",
        object(%{"id" => integer("Dashboard id")}, ["id"]),
        fn args, _ctx -> Dashboards.get(args["id"]) end
      ),
      tool(
        "save_dashboard",
        "Create or rename a dashboard. Pass id to rename.",
        object(%{"id" => integer("Dashboard id"), "name" => string("Name")}),
        fn args, _ctx ->
          Dashboards.save(%{id: args["id"], name: args["name"] || "Untitled"})
        end
      ),
      tool(
        "delete_dashboard",
        "Delete a dashboard and its cards.",
        object(%{"id" => integer("Dashboard id")}, ["id"]),
        fn args, _ctx ->
          Dashboards.delete(args["id"])
          {:ok, %{"deleted" => true, "id" => args["id"]}}
        end
      ),
      tool(
        "pin_question",
        "Pin a saved question onto a dashboard.",
        object(
          %{
            "dashboard_id" => integer("Dashboard id"),
            "question_id" => integer("Question id"),
            "date_column" => string("Optional date column for dashboard filters")
          },
          ["dashboard_id", "question_id"]
        ),
        fn args, _ctx ->
          Dashboards.add_card(args["dashboard_id"], args["question_id"], %{
            date_column: args["date_column"]
          })
        end
      ),
      tool(
        "layout_dashboard",
        "Set card positions and sizes on a dashboard (12-column board). Each card needs id, col, row, size_x, size_y.",
        object(
          %{
            "id" => integer("Dashboard id"),
            "cards" => %{
              "type" => "array",
              "description" => "Card layouts",
              "items" => %{
                "type" => "object",
                "properties" => %{
                  "id" => integer("Dashboard card id"),
                  "col" => integer("Column 0-11"),
                  "row" => integer("Row"),
                  "size_x" => integer("Width in columns"),
                  "size_y" => integer("Height in rows")
                }
              }
            }
          },
          ["id", "cards"]
        ),
        fn args, _ctx ->
          Dashboards.save_layout(args["id"], args["cards"] || [])
        end
      ),
      tool(
        "unpin_card",
        "Remove a dashboard card.",
        object(%{"card_id" => integer("Dashboard card id")}, ["card_id"]),
        fn args, _ctx ->
          Dashboards.remove_card(args["card_id"])
          {:ok, %{"deleted" => true, "id" => args["card_id"]}}
        end
      ),
      tool(
        "run_dashboard",
        "Run every card on a dashboard (optional date range) and return masked results.",
        object(
          %{
            "id" => integer("Dashboard id"),
            "from" => string("Start date YYYY-MM-DD"),
            "to" => string("End date YYYY-MM-DD")
          },
          ["id"]
        ),
        fn args, ctx ->
          with {:ok, dash} <- Dashboards.get(args["id"]) do
            cards =
              Enum.map(dash["cards"] || [], fn card ->
                sql =
                  Dashboards.wrap_date_filter(
                    card["sql"],
                    card["date_column"],
                    args["from"],
                    args["to"]
                  )

                result =
                  case Query.run(sql,
                         actor: ctx.actor,
                         database: card["database_id"],
                         question_id: card["question_id"]
                       ) do
                    {:ok, r} -> result_json(r)
                    {:error, error} -> %{"error" => error.message}
                  end

                Map.merge(%{"card_id" => card["id"], "name" => card["question_name"]}, result)
              end)

            {:ok, %{"id" => dash["id"], "name" => dash["name"], "cards" => cards}}
          end
        end
      ),
      tool(
        "list_audit",
        "Paginated audit log. SQL is redacted; result cells are never stored.",
        object(%{
          "page" => integer("Page number (1-based)"),
          "per_page" => integer("Page size 1–100")
        }),
        fn args, _ctx ->
          {:ok, Audit.page(args["page"] || 1, args["per_page"] || 25)}
        end
      ),
      tool(
        "get_settings",
        "Current engine, DuckDB status, audit retention, and attached sources.",
        %{},
        fn _args, _ctx ->
          status = DuckDB.Server.status()

          {:ok,
           %{
             "engine" => to_string(Settings.engine()),
             "duckdb_available" => status.available?,
             "duckdb_status" => to_string(status.status),
             "duckdb_error" => status.error,
             "audit_retention_days" => Settings.audit_retention_days(),
             "sources" =>
               Enum.map(Settings.sources(), fn s ->
                 %{
                   "id" => s["id"],
                   "alias" => s["alias"],
                   "kind" => s["kind"],
                   "dsn" => Settings.redact_dsn(s["dsn"]),
                   "enabled" => s["enabled"],
                   "error" => s["error"]
                 }
               end),
             "attached" =>
               Enum.map(status.attached || [], fn src ->
                 %{
                   "alias" => src.alias,
                   "kind" => src.kind,
                   "ok" => src.ok?,
                   "error" => src.error,
                   "dsn" => Settings.redact_dsn(src.dsn)
                 }
               end)
           }}
        end
      ),
      tool(
        "set_engine",
        "Switch the query engine between postgresql and duckdb.",
        object(%{"engine" => string("postgresql or duckdb")}, ["engine"]),
        fn args, _ctx ->
          with {:ok, engine} <- Settings.put_engine(args["engine"]) do
            {:ok, %{"engine" => to_string(engine)}}
          end
        end
      ),
      tool(
        "set_audit_retention",
        "Set audit retention in days (7, 30, 90, 180, 365) or 0 to keep forever.",
        object(%{"days" => integer("Retention days")}, ["days"]),
        fn args, _ctx ->
          with {:ok, days} <- Settings.put_audit_retention_days(args["days"]) do
            {:ok, %{"audit_retention_days" => days}}
          end
        end
      ),
      tool("reconnect_engine", "Reload DuckDB attachments.", %{}, fn _args, _ctx ->
        _ = DuckDB.Server.reload()
        {:ok, %{"ok" => true, "status" => inspect_status(DuckDB.Server.status())}}
      end),
      tool(
        "add_source",
        "Attach an extra DuckDB source (postgres, mysql, sqlite, duckdb, parquet, csv, json).",
        object(
          %{
            "alias" => string("SQL alias, for example billing"),
            "kind" => string("postgres, mysql, sqlite, duckdb, parquet, csv, or json"),
            "dsn" => string("Connection string, file path, or URL")
          },
          ["alias", "kind", "dsn"]
        ),
        fn args, _ctx ->
          with {:ok, source} <- Settings.add_source(args) do
            {:ok, Map.update(source, "dsn", "", &Settings.redact_dsn/1)}
          end
        end
      ),
      tool(
        "remove_source",
        "Detach an extra DuckDB source.",
        object(%{"id" => integer("Source id")}, ["id"]),
        fn args, _ctx ->
          with :ok <- Settings.delete_source(args["id"]) do
            {:ok, %{"deleted" => true, "id" => args["id"]}}
          end
        end
      ),
      tool(
        "list_protections",
        "Runtime column protection rules (global, per source, per table).",
        %{},
        fn _args, _ctx ->
          {:ok, Protection.list()}
        end
      ),
      tool(
        "add_protection",
        "Add a runtime column protection rule.",
        object(
          %{
            "scope" => string("global, source, or table"),
            "column" => string("Column name"),
            "source_id" => string("Database or DuckDB alias (required for source/table)"),
            "table" => string("Table name (required for table scope)")
          },
          ["scope", "column"]
        ),
        fn args, _ctx ->
          Protection.add(%{
            scope: args["scope"],
            column_name: args["column"] || args["column_name"],
            source_id: args["source_id"],
            table_name: args["table"] || args["table_name"]
          })
        end
      ),
      tool(
        "remove_protection",
        "Remove a runtime protection rule by id.",
        object(%{"id" => integer("Protection row id")}, ["id"]),
        fn args, _ctx ->
          with :ok <- Protection.remove(args["id"]) do
            {:ok, %{"deleted" => true, "id" => args["id"]}}
          end
        end
      ),
      tool(
        "list_integrations",
        "List email/webhook integrations (secrets redacted).",
        %{},
        fn _args, _ctx ->
          {:ok, Enum.map(Integrations.list(), &Integrations.public/1)}
        end
      ),
      tool(
        "save_email_integration",
        "Save the SMTP channel used by email alerts.",
        object(
          %{
            "host" => string("SMTP host"),
            "port" => integer("SMTP port"),
            "from" => string("From address"),
            "username" => string("SMTP username"),
            "password" => string("SMTP password"),
            "tls" => %{"type" => "boolean", "description" => "Use TLS"}
          },
          ["host", "from"]
        ),
        fn args, _ctx ->
          with {:ok, row} <- Integrations.save_email(args) do
            {:ok, Integrations.public(row)}
          end
        end
      ),
      tool(
        "add_webhook",
        "Register a named webhook for alerts.",
        object(
          %{
            "name" => string("Display name"),
            "url" => string("https://..."),
            "auth" => string("none, bearer, or header"),
            "token" => string("Bearer token or API key")
          },
          ["name", "url"]
        ),
        fn args, _ctx ->
          with {:ok, row} <- Integrations.add_webhook(args) do
            {:ok, Integrations.public(row)}
          end
        end
      ),
      tool(
        "remove_webhook",
        "Delete a webhook integration.",
        object(%{"id" => integer("Integration id")}, ["id"]),
        fn args, _ctx ->
          with :ok <- Integrations.delete(args["id"]) do
            {:ok, %{"deleted" => true, "id" => args["id"]}}
          end
        end
      ),
      tool("list_alerts", "List saved-question alerts.", %{}, fn _args, _ctx ->
        {:ok, Alerts.list()}
      end),
      tool(
        "create_alert",
        "Create an alert on a saved question (email and/or webhooks).",
        object(
          %{
            "question_id" => integer("Saved question id"),
            "condition" => string("rows, no_rows, above, or below"),
            "threshold" => string("Goal value for above/below"),
            "schedule" => string("1m, 5m, 15m, 1h, 6h, or 1d"),
            "once" => %{"type" => "boolean"},
            "emails" => string("Comma-separated recipients"),
            "webhook_ids" => %{"type" => "array", "items" => %{"type" => "integer"}}
          },
          ["question_id"]
        ),
        fn args, _ctx -> Alerts.save(args) end
      ),
      tool(
        "delete_alert",
        "Delete an alert.",
        object(%{"id" => integer("Alert id")}, ["id"]),
        fn args, _ctx ->
          with :ok <- Alerts.delete(args["id"]) do
            {:ok, %{"deleted" => true, "id" => args["id"]}}
          end
        end
      ),
      tool(
        "run_alert",
        "Run an alert now (sends if the condition is met, or always when force is true).",
        object(%{"id" => integer("Alert id"), "force" => %{"type" => "boolean"}}, ["id"]),
        fn args, ctx ->
          PhoenixLens.Alerts.Runner.run_one(args["id"],
            force: args["force"] == true,
            actor: ctx.actor
          )
        end
      )
    ]
  end

  defp tool(name, description, schema, fun) do
    schema =
      schema
      |> Map.put_new("type", "object")
      |> Map.put_new("properties", %{})
      |> Map.put_new("additionalProperties", false)

    {name, %{description: description, schema: schema}, fun}
  end

  defp object(properties, required \\ []) do
    %{
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }
  end

  defp string(desc), do: %{"type" => "string", "description" => desc}
  defp integer(desc), do: %{"type" => "integer", "description" => desc}

  defp table_json(table) do
    %{
      "name" => table.source,
      "module" => table.module,
      "fields" =>
        Enum.map(table.fields, fn f ->
          %{
            "name" => f.name,
            "type" => to_string(f.type),
            "protected" => f.protected
          }
        end)
    }
  end

  defp result_json(%Result{} = result) do
    %{
      "columns" => result.columns,
      "rows" => Enum.map(result.rows, fn row -> Enum.map(row, &json_cell/1) end),
      "masked_columns" => result.masked_columns,
      "num_rows" => result.num_rows,
      "truncated" => result.truncated,
      "duration_ms" => result.duration_ms,
      "database_id" => result.database_id,
      "sql" => result.sql
    }
  end

  defp json_cell(:redacted), do: Result.redacted_label()
  defp json_cell(nil), do: nil
  defp json_cell(value) when is_number(value) or is_boolean(value), do: value
  defp json_cell(value), do: Result.display_cell(value)

  defp sql_from_args(%{"sql" => sql} = args) when is_binary(sql) and sql != "" do
    {:ok, sql, args["database_id"] || "primary", args["question_id"]}
  end

  defp sql_from_args(args) do
    case args["question_id"] || args["id"] do
      nil ->
        {:error, "sql or question_id is required"}

      id ->
        case Questions.get(id) do
          {:ok, q} -> {:ok, q["sql"], q["database_id"], q["id"]}
          other -> other
        end
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp stringify_keys(_), do: %{}

  defp down(nil), do: ""
  defp down(v), do: v |> to_string() |> String.downcase()

  defp inspect_status(status) do
    %{
      "available" => status.available?,
      "status" => to_string(status.status),
      "error" => status.error
    }
  end
end
