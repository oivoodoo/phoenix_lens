# Lens (`phoenix_lens`)

Mountable SQL notebook for Phoenix. Point it at your Ecto Repo, save questions, pin dashboards, and **mask PII/PHI in every output**.

This is not Metabase. It is the PgHero-shaped tool you mount at `/lens` so you can stop giving a sidecar JVM a god-mode DB user.

## Install

```elixir
def deps do
  [{:phoenix_lens, "~> 0.1.0"}]
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

Then open `/lens`. Prefer a read replica; see [docs/Phoenix.md](docs/Phoenix.md).

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

- [Phoenix mount](docs/Phoenix.md)
- [Field policy](docs/Policy.md)
- [Permissions](docs/Permissions.md)
- [Spec](docs/spec.md)
