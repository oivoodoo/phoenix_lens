# Lens (`phoenix_lens`)

Mountable SQL notebook for Phoenix. Point it at your Ecto Repo, save questions, pin dashboards, and **mask PII/PHI in every output**.

This is not Metabase. It is the PgHero-shaped tool you mount at `/lens` so you can stop giving a sidecar JVM a god-mode DB user.

## Install

```elixir
def deps do
  [{:phoenix_lens, "~> 0.1.4"}]
end
```

```elixir
config :phoenix_lens,
  repo: MyApp.Repo,
  masked_fields: [:email, :first_name, :last_name, :phone]
```

Ecto fields marked `redact: true` are protected automatically.

```elixir
import PhoenixLensWeb.Router

scope "/" do
  pipe_through [:browser, :require_admin]
  lens "/lens"
end
```

```elixir
defmodule MyApp.Repo.Migrations.AddPhoenixLens do
  use Ecto.Migration
  def up, do: PhoenixLens.Migrations.up()
  def down, do: PhoenixLens.Migrations.down()
end
```

Then open `/lens`. Prefer a read replica. Product tour, query design, and dummy-app screenshots: [docs/Guide.md](docs/Guide.md). Mount details: [docs/Phoenix.md](docs/Phoenix.md). MCP server (agents): [docs/MCP.md](docs/MCP.md).

## DuckDB engine

Default queries go straight to PostgreSQL. In `/lens/settings` you can switch the query engine to **DuckDB**. Lens then:

1. Starts an in-process DuckDB
2. Attaches the host Ecto Repo read-only as `repo` (`INSTALL postgres; ATTACH … (TYPE postgres, READ_ONLY)`)
3. Lets you attach extra Postgres URLs, SQLite, DuckDB files, Parquet, CSV, or JSON to the **same** engine

Host tables stay queryable as `users` or `repo.users`. Extra databases are `alias.table`. File sources become a view named after the alias.

Join across sources in one question, for example Postgres + MySQL + a remote CSV:

```sql
SELECT u.id, b.sku, p.plan
FROM repo.users u
JOIN billing.orders b ON b.user_id = u.id
JOIN plans p ON p.user_id = u.id
```

DuckDB is optional. Add the NIF to the **host** app (the dummy app already does):

```elixir
def deps do
  [
    {:phoenix_lens, "~> 0.1.4"},
    {:duckdbex, "~> 0.4"}
  ]
end
```

Questions, dashboards, settings, and the audit log still live on the host Repo. Field policy still runs on every DuckDB result.

## MCP server

Agents can drive the same notebook over [Model Context Protocol](https://modelcontextprotocol.io) at `/lens/mcp`. After `Plug.Parsers` in the host endpoint:

```elixir
plug PhoenixLensWeb.Plugs.MCP, path: "/lens/mcp"
```

**Settings → MCP** issues a project token id (`plt_…`) and a one-time secret (`lns_…`). Clients send `Authorization: Bearer <secret>`. Tools cover catalog, SQL, questions, dashboards, audit, engines, sources, and column protection. Masked cells stay `[redacted]`.

```json
{
  "mcpServers": {
    "phoenix-lens": {
      "url": "http://localhost:4000/lens/mcp",
      "headers": {
        "Authorization": "Bearer lns_…"
      }
    }
  }
}
```

Details: [docs/MCP.md](docs/MCP.md).

## Alerts

Saved questions can notify **email** or a **webhook** when they return rows, return none, or cross a numeric goal. Configure SMTP and webhook URLs in **Settings → Integrations**, then click **Alert** on a question.

Payloads are field-policy masked. Email sending needs `{:gen_smtp, "~> 1.2"}` in the host app. See [docs/Alerts.md](docs/Alerts.md).

## Security lock

**Settings → Security** can turn on an authenticator app (TOTP) and register passkeys. After either is enabled, the UI asks for that factor at `/lens/unlock`. This is an extra lock on the notebook, not a replacement for the host pipeline. MCP tokens skip it. If you lock yourself out: `PhoenixLens.Auth.reset!()` in IEx.

## Dummy app

```sh
cd dummy
docker compose up -d
mix setup
mix phx.server
```

Open [http://localhost:4000/lens](http://localhost:4000/lens) and run:

```sql
SELECT id, email AS contact, first_name FROM users
```

`contact` and `first_name` render as `[redacted]`.

## Compliance posture

Designed so the dashboard path does not emit configured PII/PHI (grid, CSV, embeds, logs, audit). 

This library is **not** HIPAA or GDPR certified. You are the operator. Mount behind your own auth, prefer a read replica, and do not confuse IEx/`Repo.get` with this dashboard.

Threat model: [docs/Policy.md](docs/Policy.md).

## Standalone

```sh
DATABASE_URL=postgres://user:pass@localhost/dbname mix phoenix_lens.server
```

Then visit `http://localhost:8080/lens`.

## Docs

- [Guide](https://oivoodoo.github.io/phoenix_lens/guide.html) — features, query design, DuckDB vs PostgreSQL, screenshots ([source](docs/Guide.md))
- [MCP](docs/MCP.md) — agent endpoint, project tokens
- [Alerts](docs/Alerts.md) — email and webhook notifications
- [HexDocs](https://hexdocs.pm/phoenix_lens)
- [Phoenix mount](docs/Phoenix.md)
- [Field policy](docs/Policy.md)
- [Permissions](docs/Permissions.md) — host pipeline plus optional 2FA / passkeys
- [Spec](docs/spec.md)
