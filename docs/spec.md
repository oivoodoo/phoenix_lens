# Spec: phoenix_lens (Lens)

Living spec. Idea one-pager: `docs/ideas/lens.md` (workspace root). ADRs: `docs/decisions/`.

**Status:** v0.1.0 implemented in this directory. This spec remains the contract.

## Assumptions (correct these before coding)

1. **Name.** Product: Lens. Hex + OTP app: `phoenix_lens` (`lens` is taken on Hex and would collide with the `Lens` module). Elixir modules: `PhoenixLens`, `PhoenixLensWeb`. Router macro: `lens "/lens"`.
2. **Audience.** Phoenix developers / ops, not PMs. SQL is the interface. Host `:require_admin` (or equivalent) is the permission model.
3. **Replacement.** v1 exists to uninstall a Metabase sidecar for *this* user, not to win a BI bake-off.
4. **Default engine PostgreSQL** (Postgrex). Optional DuckDB engine attaches the host Repo read-only and extra sources (Postgres, SQLite, DuckDB files, Parquet, CSV, JSON) in one in-process engine. Host apps add `{:duckdbex, "~> 0.4"}`.
5. **Auth.** None inside the library when mounted. Optional HTTP basic auth (PgHero pattern). Identity for audit: `conn.assigns[:current_user]` (configurable assign key); stringified; `"anonymous"` if missing.
6. **Mask default.** Protected cells become the atom `:redacted`, rendered `[redacted]`. WHERE may reference protected columns. Stored SQL / audit viewer redact email- and phone-like literals.
7. **Not certified.** README says designed for GDPR/HIPAA dashboard use (minimization, audit, no PHI in sinks). No “compliant” / “certified” claim.
8. **Stack.** Elixir `~> 1.15`, Phoenix `~> 1.7`, LiveView `~> 0.20 or ~> 1.0`, Ecto SQL `~> 3.11`, Postgrex `~> 0.17`, Jason, Bandit for dummy/standalone. MIT license. Mirror PgHero’s dummy-app + `mix phoenix_lens.server` layout.
9. **Persistence.** Questions, dashboards, and audit rows live in the **host** Repo via `PhoenixLens.Migrations`. Query *results* are never stored.
10. **Alerts, GUI query builder, collections, result cache, AI** are out of v1.

→ Correct these now or they become the contract.

## Objective

Phoenix developers mount an analytics notebook in their existing app, pointed at their Ecto Repo (preferably a replica), and can:

- browse Ecto schemas / tables as a catalog (types, associations, which fields are protected)
- run **read-only** SQL
- save, rename, re-run questions
- pin questions onto a dashboard (optional date-range filter)
- embed a saved question in a host LiveView
- export CSV that is still masked
- trust that configured PII/PHI fields never appear in any Lens output

Success is: five recurring Metabase questions can be saved here, a dashboard rendered, and a test suite that fails if `email` leaks through an alias, CSV, log, or embed.

### User stories

1. As an admin, I add `{:phoenix_lens, "~> 0.1"}`, set `repo:` + `masked_fields:`, mount `lens "/lens"` behind `:require_admin`, run `PhoenixLens.Migrations.up/0`, and open `/lens`.
2. As an admin, I write `SELECT id, email, inserted_at FROM users LIMIT 50`, see `id` and `inserted_at` in the clear and `email` as `[redacted]`, including if I write `SELECT email AS contact`.
3. As an admin, I save that SQL as “Recent users”, pin it on “Ops”, and reopen `/lens` later to see the same card.
4. As an admin, I download CSV and still see `[redacted]` in the email column.
5. As a host-app developer, I render `<PhoenixLens.Components.QuestionCard id="recent-users" question_id={id} />` in my own LiveView and get the same policy.
6. As an auditor, I query `phoenix_lens_audit` and see who ran what (redacted SQL, hash, row count, duration) and never see result cells.

## Tech Stack

| Piece | Choice |
| --- | --- |
| Language | Elixir ~> 1.15 |
| Web | Phoenix ~> 1.7, Phoenix LiveView, Phoenix HTML, Plug |
| DB | Ecto SQL ~> 3.11, Postgrex ~> 0.17 |
| JSON | Jason |
| Dummy / standalone HTTP | Bandit ~> 1.5 |
| Charts v1 | HTML table + one numeric/KPI card + simple SVG bar/line (no Vega, no npm) |
| License | MIT |

No Oban, no Cloak, no SQL parser dependency in v1. Origin columns come from the Postgres protocol + `pg_catalog`.

## Commands

From `phoenix_lens/`:

```
mix deps.get
mix format
mix test
mix test --include integration    # requires DATABASE_URL
mix compile --warnings-as-errors
```

Dummy app (`phoenix_lens/dummy/`):

```
cd dummy && mix setup && mix phx.server
# open http://localhost:4000/lens
```

Standalone (optional, PgHero parity, later if it does not block MVP):

```
DATABASE_URL=postgres://... mix phoenix_lens.server
```

Host app:

```
mix ecto.gen.migration add_phoenix_lens
# def up, do: PhoenixLens.Migrations.up()
mix ecto.migrate
```

## Project Structure

```
phoenix_lens/
  mix.exs
  README.md
  CHANGELOG.md
  LICENSE.txt
  .formatter.exs
  docs/
    spec.md                          ← this file
    decisions/                       ← ADRs
    Phoenix.md                       ← mount guide
    Policy.md                        ← field policy + threat model
    Permissions.md                   ← host auth, replica user
  lib/
    phoenix_lens.ex                  ← public API
    phoenix_lens/
      application.ex
      config.ex                      ← repo / databases / policy / timeouts
      policy.ex                      ← merge protected fields, apply to results
      catalog.ex                     ← Ecto schemas + table/column listing
      query.ex                       ← read-only execute + origin columns
      redactor.ex                    ← SQL literal redaction for storage/logs
      audit.ex
      questions.ex
      dashboards.ex
      migrations.ex
      result.ex                      ← struct: columns, rows (already masked), meta
    phoenix_lens_web.ex
    phoenix_lens_web/
      router.ex                      ← defmacro lens/2
      plugs/dashboard.ex
      live/
        home_live.ex                 ← catalog + SQL editor + results
        question_live.ex
        dashboard_live.ex
        audit_live.ex
      components/
        question_card.ex             ← public embed
        result_table.ex
      layouts/
      controllers/asset_controller.ex
    mix/tasks/phoenix_lens.server.ex
  priv/static/                       ← CSS only
  dummy/                             ← host Phoenix app with PII schemas
  test/
    phoenix_lens/
      policy_test.exs                ← alias, expression, redact: true
      query_test.exs                 ← read-only rejects DML (integration)
      redactor_test.exs
      config_test.exs
    phoenix_lens_web/
      router_macro_test.exs
    support/
```

## Public API

```elixir
# config/config.exs
config :phoenix_lens,
  repo: MyApp.Repo,
  masked_fields: [:email, :first_name, :last_name, :phone, :ssn, :date_of_birth],
  masked_fields_by_source: %{
    "analytics" => [:ip]
  },
  timeout_ms: 5_000,
  max_rows: 10_000,
  actor_assign: :current_user

# optional replica, PgHero shape
config :phoenix_lens,
  databases: [
    primary: [repo: MyApp.Repo],
    analytics: [url: System.get_env("ANALYTICS_DATABASE_URL"), name: "Analytics"]
  ]

# router.ex
import PhoenixLensWeb.Router

scope "/" do
  pipe_through [:browser, :require_admin]
  lens "/lens"
end

# migration
defmodule MyApp.Repo.Migrations.AddPhoenixLens do
  use Ecto.Migration
  def up, do: PhoenixLens.Migrations.up()
  def down, do: PhoenixLens.Migrations.down()
end

# programmatic (and the only way LiveViews talk to the database)
PhoenixLens.run(sql, database: :primary, actor: user)
# => {:ok, %PhoenixLens.Result{}} | {:error, %PhoenixLens.Error{}}

PhoenixLens.Questions.save!(%{name: "Recent users", sql: sql})
PhoenixLens.Components.QuestionCard  # live_component
```

`PhoenixLens.Result` is **always** policy-applied. There is no `run_unmasked/2` in the public API.

## Field policy

Protected names (case-insensitive, ignore `_` vs camelCase after downcasing and stripping non-alnum? **No** — match on downcased exact identifier: `"email"` matches `email` / `Email` / `"Email"`; does not match `email_hash` unless listed).

Sources, merged:

1. Global `masked_fields`
2. `masked_fields_by_source[database_id]`
3. All compiled Ecto schema fields with `redact: true` (scan `repo.config` app modules via `:application.get_key(app, :modules)` filtered by `function_exported?(&__schema__/1)`). Always include those names globally (not only that table) in v1 — simpler and safer. Document that `redact: true` on `User.email` also masks a column named `email` on other tables.

Apply (`PhoenixLens.Policy.apply/2`):

1. For each result column, `origin_name` from table OID + attnum (`pg_attribute`), and `output_name` from the alias.
2. Protected if `output_name` **or** `origin_name` is in the set.
3. If no origin (computed expression): protected if the corresponding SELECT-list snippet (best-effort: output name plus full SQL identifier scan) contains a protected identifier as a whole word. If we cannot split SELECT items reliably, **scan the entire SQL** for protected identifiers and, when any are present, mask computed columns only (origin columns still use origin matching). Prefer splitting on SELECT items with a conservative parser: parentheses-aware comma split of the SELECT list; if split fails, mask all origin-less columns when SQL contains a protected identifier.
4. Replace cell values with `:redacted`. Do not inspect cell contents to “detect PII” (no regex on values — that is a side channel and a performance trap).
5. `meta.masked_columns` lists output names that were masked. `meta.truncated` if row cap hit.

SQL literal redaction (`PhoenixLens.Redactor.sql/1`) for storage, logs, and the editor’s “saved” view:

- Replace RFC-like emails and long digit runs (phones) inside quotes with `'[redacted]'`
- Do not attempt to be a full DLP product

### Query execution

`PhoenixLens.Query.run/3`:

1. Reject empty SQL.
2. Strip one trailing `;`. If another `;` remains, error `"one statement only"`.
3. First keyword (comments/`/* */` stripped) must be `SELECT` or `WITH`. `EXPLAIN` allowed only as `EXPLAIN` / `EXPLAIN ANALYZE` wrapping SELECT/WITH; the result of EXPLAIN is text and is still passed through the redactor (plan text can contain literals).
4. Reject (case-insensitive keyword presence as whole words): `INSERT` `UPDATE` `DELETE` `MERGE` `DROP` `ALTER` `CREATE` `GRANT` `REVOKE` `TRUNCATE` `COPY` `CALL` `DO` `LISTEN` `NOTIFY` `SECURITY` `SET` `INTO` `VACUUM` `REINDEX` `CLUSTER` `LOCK`.
5. Checkout from the configured Repo or Postgrex URL connection.
6. `BEGIN` → `SET LOCAL transaction_read_only = on` → `SET LOCAL statement_timeout = '<timeout_ms>'` → execute → `COMMIT` / `ROLLBACK`.
7. Capture column names and, via protocol / `pg_catalog`, origin table OID + attnum.
8. Apply policy. Truncate rows to `max_rows`.
9. Write audit row (redacted SQL, hash, actor, row count, duration, masked columns, truncated, error).
10. Return `%PhoenixLens.Result{}`.

If execute raises, audit the error (no row payload), return `{:error, _}`.

### Data model (host Repo)

Prefix `phoenix_lens_`.

```
phoenix_lens_questions
  id              bigserial PK
  name            text NOT NULL
  sql             text NOT NULL
  viz             text NOT NULL DEFAULT 'table'   -- table | number | bar | line
  database_id     text NOT NULL DEFAULT 'primary'
  inserted_at     utc_datetime_usec
  updated_at      utc_datetime_usec

phoenix_lens_dashboards
  id              bigserial PK
  name            text NOT NULL
  inserted_at     utc_datetime_usec
  updated_at      utc_datetime_usec

phoenix_lens_dashboard_cards
  id              bigserial PK
  dashboard_id    bigint REFERENCES phoenix_lens_dashboards
  question_id     bigint REFERENCES phoenix_lens_questions
  position        int NOT NULL
  date_column     text                    -- optional column name for dashboard filter
  inserted_at     utc_datetime_usec

phoenix_lens_audit
  id              bigserial PK
  actor           text NOT NULL
  database_id     text NOT NULL
  question_id     bigint NULL
  sql_redacted    text NOT NULL
  query_hash      text NOT NULL           -- sha256 of canonical sql
  row_count       int
  duration_ms     int
  masked_columns  text[]
  truncated       boolean NOT NULL DEFAULT false
  error           text
  inserted_at     utc_datetime_usec
```

Indexes: `phoenix_lens_audit(inserted_at DESC)`, `phoenix_lens_audit(query_hash)`.

No foreign-key cascade from questions into audit (keep history if a question is deleted; `question_id` nullable).

### UI (v1)

LiveViews, not controllers, for the notebook. Layout is a single left-nav (PgHero energy: dense, not a SaaS marketing page).

| Route | Purpose |
| --- | --- |
| `GET /` | SQL editor + result table + Save |
| `GET /catalog` | Ecto schemas / tables, field names, protected badge |
| `GET /questions` | list |
| `GET /questions/:id` | run saved, edit SQL, viz type |
| `GET /dashboards` | list |
| `GET /dashboards/:id` | cards; optional `?from=&to=` applied as `WHERE date_column >= from AND date_column < to` **only if** `date_column` is set and is not protected |
| `GET /audit` | recent runs, redacted SQL |
| `GET /questions/:id/csv` | masked CSV |

Dashboard date filter is a query-parameter rewrite, not a SQL parser party: wrap `SELECT * FROM (question_sql) q WHERE q.<date_column> >= $1 AND q.<date_column> < $2`. If wrap fails, show the card error, do not skip policy.

### Embed

```heex
<.live_component
  module={PhoenixLens.Components.QuestionCard}
  id={"q-#{question.id}"}
  question_id={question.id}
/>
```

Runs `PhoenixLens.run/2` with the host actor. Same policy.

## Code Style

Formatter: `mix format` with `import_deps: [:phoenix, :ecto, :ecto_sql]`, LiveView HTMLFormatter. Mirror PgHero: `PgHero`-style short functions, no GenServers unless we need a connection pool for `url:` databases (then the PgHero `Postgrex.child_spec` pattern).

Public modules have `@moduledoc`. Internal modules `@moduledoc false`.

Example of the contract we will not violate:

```elixir
defmodule PhoenixLens.Policy do
  @moduledoc false

  @type column :: %{name: String.t(), origin: String.t() | nil}
  @type row :: [term()]

  @spec apply([column()], [row()], MapSet.t(String.t())) ::
          {[column()], [row()], [String.t()]}
  def apply(columns, rows, protected) do
    flags =
      Enum.map(columns, fn col ->
        protected?(col.name, protected) or protected?(col.origin, protected)
      end)

    masked_names =
      columns
      |> Enum.zip(flags)
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(fn {col, _} -> col.name end)

    rows =
      Enum.map(rows, fn row ->
        row
        |> Enum.zip(flags)
        |> Enum.map(fn {value, true} -> :redacted; {value, false} -> value end)
      end)

    {columns, rows, masked_names}
  end

  defp protected?(nil, _), do: false
  defp protected?(name, set), do: MapSet.member?(set, String.downcase(name))
end
```

Errors are `%PhoenixLens.Error{message: _, kind: :sql | :policy | :timeout | :read_only}`.

## Testing Strategy

ExUnit. Default `mix test` does **not** need Postgres (`integration` tagged, same as PgHero).

| Layer | File | What must fail if broken |
| --- | --- | --- |
| Policy unit | `policy_test.exs` | alias `email AS contact` masked when origin is `email`; `redact: true` field names included; unprotected columns intact; computed column + SQL containing `email` masked |
| Redactor unit | `redactor_test.exs` | `'a@b.com'` in SQL becomes `'[redacted]'`; audit payload never contains that literal |
| Config unit | `config_test.exs` | `repo:` vs `databases:`; env overrides |
| Router | `router_macro_test.exs` | `lens "/lens"` compiles and prefixes parent scopes |
| Query integration | `query_test.exs` | `DELETE` rejected; `SELECT` works; statement timeout; row cap sets `truncated`; origin mask on real Postgres |
| Web integration | dummy or `ConnCase` | CSV body has `[redacted]`, not the seeded email; LiveView result table too |

Seed data in integration: a `users` table with `email = 'alice@example.com'`, `first_name = 'Alice'`. Tests assert the string `alice@example.com` does **not** appear in Result, CSV, rendered HTML, or audit `sql_redacted` when the saved SQL used a literal.

Coverage target: policy + query + redactor at 100% of branches that can leak; no vanity global %.

## Boundaries

**Always**

- Run `mix format` and `mix test` before considering a slice done
- Put every result through `PhoenixLens.Policy` before it leaves `PhoenixLens.Query`
- Keep questions/audit migrations in `PhoenixLens.Migrations`
- Document threat-model limitations in `docs/Policy.md` (subquery smuggling, IEx `Repo` bypass, EXPLAIN literals)

**Ask first**

- Adding Hex dependencies
- Changing the public `PhoenixLens` API or config keys
- GUI query builder, alerts, permissions, non-Postgres adapters
- Storing result rows
- Any README language that says “compliant” or “certified”
- Hex publish / version bump

**Never**

- A public `run_unmasked` (or equivalent flag that reaches the browser)
- Logging result rows
- Executing more than one statement per request
- Writing DML/DDL through Lens
- Shipping a user/login system inside the library
- Claiming HIPAA/GDPR certification
- Matching PII by scanning cell values with regex as the primary control

## Success Criteria

v0.1.0 is done when all of the following are true:

1. Dummy app mounts at `/lens` with `masked_fields: [:email, :first_name]` and a `User` schema with `redact: true` on `email`.
2. SQL editor runs `SELECT id, email AS contact, first_name FROM users` and the grid shows `[redacted]` for `contact` and `first_name`, raw `id`.
3. The same query’s CSV matches that masking; the file does not contain `alice@example.com`.
4. `DELETE FROM users` returns a read-only error and does not change dummy data.
5. Saving the SELECT, pinning it to a dashboard, and reloading shows the card.
6. `phoenix_lens_audit` has a row with redacted SQL, actor, row count; no result cells.
7. `mix test` (no Docker) is green; `mix test --include integration` is green with `DATABASE_URL`.
8. README install is the PgHero three-step (dep, config, mount) plus migration and `masked_fields`.
9. README states: designed to keep PII/PHI out of dashboard sinks; not a certification; mount behind auth; prefer a replica; IEx/Repo is out of scope.

## Out of scope (v1)

- GUI query builder / notebook “join clicker”
- Alerts / email pulses (must not ship until they call the same policy)
- Collections, groups, SSO, row-level sandboxing
- Result caching
- Multi-engine (MySQL, BigQuery, Snowflake)
- AI / NL-to-SQL
- Docker image (nice-to-have after dummy works; PgHero has one — do not block 0.1.0)
- `strict:` reject-if-touches-PHI mode

## Open Questions

Resolved in this spec unless you override:

| Question | Locked |
| --- | --- |
| Hex name | `phoenix_lens` |
| Mask vs strip vs hash | mask (`:redacted`) |
| Protected in WHERE | allowed |
| Postgres only | yes |
| Strict deny mode | not v1 |

Still open:

- GitHub repo name / GitHub org (assume `oivoodoo/phoenix_lens` to match PgHero)
- Standalone `mix phoenix_lens.server` in 0.1.0 or 0.2.0
- Whether dashboard date-filter wrap is in 0.1.0 or dashboards are just stacked cards with no filter
