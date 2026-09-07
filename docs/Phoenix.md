# Phoenix

## Installation

Add PhoenixLens to `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_lens, "~> 0.1.3"}
  ]
end
```

Configure a database and the fields that must never appear in outputs:

```elixir
config :phoenix_lens,
  repo: MyApp.Repo,
  masked_fields: [:email, :first_name, :last_name, :phone]
```

Ecto schema fields with `redact: true` are protected automatically in addition to this list.

Mount the dashboard in `router.ex`. Always put it behind authentication in production.

```elixir
import PhoenixLensWeb.Router

scope "/" do
  pipe_through [:browser, :require_admin]
  lens "/lens"
end
```

Create the tables:

```elixir
defmodule MyApp.Repo.Migrations.AddPhoenixLens do
  use Ecto.Migration

  def up, do: PhoenixLens.Migrations.up()
  def down, do: PhoenixLens.Migrations.down()
end
```

Then open `/lens`. Screenshots and query-engine details: [Guide.md](Guide.md). MCP server: [MCP.md](MCP.md).

The SQL editor autocompletes tables and columns from Ecto schemas (and `information_schema` when a repo is configured). Type after `FROM` / `JOIN` for tables, `users.` for that table’s columns, or a prefix in `SELECT` / `WHERE`. Tab or Enter inserts. Protected columns are labelled redacted.

Parent scopes are included in generated URLs.

The host `:browser` pipeline should include `:fetch_session`, `:fetch_live_flash`, and `:protect_from_forgery`. The host endpoint must already have a LiveView socket at `/live`.

## Authentication

PhoenixLens does **not** authenticate by itself when you mount it in a Phoenix pipeline. Put it behind your admin plug.

Optional HTTP basic auth:

```elixir
config :phoenix_lens,
  username: System.get_env("PHOENIX_LENS_USERNAME"),
  password: System.get_env("PHOENIX_LENS_PASSWORD")
```

**Do not expose this dashboard on the public internet without auth.**

**Settings → Security** can add an extra UI lock: TOTP from an authenticator app, and/or passkeys. When either is enabled, `/lens` redirects to `/lens/unlock` until the session is unlocked. MCP requests are not gated by this lock. It is not a replacement for the host pipeline.

If you lock yourself out:

```elixir
iex> PhoenixLens.Auth.reset!()
```

Passkeys use WebAuthn against the page origin (`http://localhost:4000` in the dummy app). HTTPS is required everywhere except localhost.

## Multiple databases

```elixir
config :phoenix_lens,
  repo: MyApp.Repo,
  databases: [
    primary: [repo: MyApp.Repo],
    analytics: [url: System.get_env("ANALYTICS_DATABASE_URL"), name: "Analytics"]
  ]
```

Questions, dashboards, settings, and the audit log always persist on `repo:`. Point the query target at a **read replica** when you can. Audit is paginated; Settings sets how long rows are kept (7–365 days, or forever). Default is 90 days.

**Column protection** (`/lens/settings/protection`) adds runtime masks on top of `masked_fields` and Ecto `redact: true`: globally, per database/source, or per table.

**MCP** (`/lens/settings/mcp`) issues project tokens for the agent endpoint. See below.

## MCP

After `Plug.Parsers` in the host endpoint, mount the MCP server so agents can use the same notebook behind a project token:

```elixir
plug PhoenixLensWeb.Plugs.MCP, path: "/lens/mcp"
```

Issue tokens in **Settings → MCP**. Clients POST JSON-RPC to `{mount}/mcp` with `Authorization: Bearer <secret>`. Field policy still applies. Full tool list: [MCP.md](MCP.md). Product tour: [Guide.md](Guide.md).

## Alerts

**Settings → Integrations** stores SMTP and named webhook URLs. On a saved question, **Alert** checks the question on a schedule (1m–daily) and emails or POSTs JSON when:

- it returns any rows (or no rows)
- a numeric value goes above or below a goal

Optional `{:gen_smtp, "~> 1.2"}` for outbound mail. Webhooks use `:httpc`. See [Alerts.md](Alerts.md).

## DuckDB engine

`/lens/settings` can switch the query engine from PostgreSQL to DuckDB. DuckDB attaches the host Repo read-only as `repo` and any extra sources you add (Postgres, MySQL, SQLite, DuckDB files, Parquet, CSV, JSON). Join them in one question (`repo.users`, `billing.orders`, a CSV view). The host app must depend on `{:duckdbex, "~> 0.4"}`. User SQL is still SELECT-only; `ATTACH` is not allowed in the editor.

## Embed a question

```heex
<.live_component
  module={PhoenixLens.Components.QuestionCard}
  id={"q-#{id}"}
  question_id={id}
  actor={@current_user}
/>
```

The same field policy applies.
