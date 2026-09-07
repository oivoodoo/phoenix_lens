# Dummy Phoenix app

A host application used to try the PhoenixLens mount.

## Run

From this directory:

```sh
docker compose up -d
mix setup
mix phx.server
```

Postgres is published on **5556** (host) → 5432 (container). Optional MySQL is on **3307** (`MYSQL_URL=mysql://lens:mysql@127.0.0.1:3307/lens_test`).

Then open:

- [http://localhost:4000](http://localhost:4000) — dummy home
- [http://localhost:4000/lens](http://localhost:4000/lens) — notebook
- [http://localhost:4000/lens/settings](http://localhost:4000/lens/settings) — switch PostgreSQL ↔ DuckDB and attach extra sources

Screenshots and a walkthrough of those pages: [../docs/Guide.md](../docs/Guide.md).

If tables already exist from an older dummy setup:

```sh
mix ecto.reset
```

Tables: `users`, `orders`, `posts`, `comments`, `logs`, `subscriptions`.

Try:

```sql
SELECT id, email AS contact, first_name FROM users
```

`contact` and `first_name` should render as `[redacted]`. The string `alice@example.com` must not appear.

```sql
SELECT plan, status, count(*) FROM subscriptions GROUP BY 1, 2
SELECT event, status_code, count(*) FROM logs GROUP BY 1, 2
SELECT category, status, count(*) FROM posts GROUP BY 1, 2
```
