# ADR-003: PostgreSQL only, prefer replica, hard timeout and row cap

## Status
Accepted

## Date
2026-09-04

## Context
Lens executes analyst SQL against the host app’s data. The host Repo is typically the primary OLTP database. A Metabase-style `GROUP BY` on `events` can take down checkout. Origin-column masking also needs PostgreSQL `RowDescription` table OID + attnum.

PgHero already supports `repo:` and `url:` per named database, including replicas.

## Decision
- v1 dialect is **PostgreSQL only** (Postgrex). Other Ecto adapters are out of scope.
- Config mirrors PgHero: `repo:` and/or `databases:` with optional `url:` for a read replica.
- Every query runs in a checkout with `SET LOCAL transaction_read_only = on` and `SET LOCAL statement_timeout`.
- Results are hard-capped (`max_rows`, default 10_000). Truncation is visible in the UI and the audit row.
- README default is: point `/lens` at a replica, not the primary.

## Alternatives Considered

### Any Ecto adapter
- Pros: MySQL/SQLite apps
- Cons: Origin-column resolution and read-only transaction semantics differ; SQL editor implies a dialect
- Rejected for v1.

### No timeout; trust the analyst
- Pros: Simpler
- Cons: One forgotten `LIMIT` pages the on-call
- Rejected.

## Consequences
- Dummy app and CI use Postgres (same as PgHero)
- MySQL users are told “not now” in the README
- Statement timeout and row cap are part of the public config contract
