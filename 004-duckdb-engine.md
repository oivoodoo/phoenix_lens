# ADR-004: Optional DuckDB engine in front of Postgres and extra sources

## Status
Accepted

## Date
2026-09-06

## Context
Lens v1 queries PostgreSQL through Ecto/Postgrex. Analysts also want one engine that can join the host Repo with warehouse Postgres, SQLite, Parquet, and CSV without standing up another BI sidecar. DuckDB’s postgres scanner can `ATTACH` a running Postgres as read-only and keep additional attachments on the same connection.

## Decision
- Default engine remains **PostgreSQL** (direct, read-only transaction + statement_timeout).
- Settings persist `engine` (`postgresql` | `duckdb`) and extra sources on the host Repo.
- DuckDB is optional: host apps add `{:duckdbex, "~> 0.4"}`. Without it, Settings still render and switching explains the missing dep.
- When DuckDB is on, one in-memory DuckDB attaches the host Repo as `repo` (`TYPE postgres, READ_ONLY`) plus user sources. Field policy still applies to result rows.
- User SQL stays SELECT/WITH/EXPLAIN. Attach/load/install happen only inside the engine, not the notebook.

## Alternatives Considered

### Always-on DuckDB
- Pros: one code path
- Cons: NIF + extension download in every host; extra failure mode for the default Postgres notebook
- Rejected as the default.

### Separate DuckDB process / MotherDuck
- Pros: isolation
- Cons: another sidecar, the thing Lens exists to avoid
- Rejected.

## Consequences
- Dummy app depends on duckdbex so `/lens/settings` can actually switch.
- Catalog lists attached DuckDB tables when the engine is DuckDB.
- Origin-column masking still uses the SELECT list; DuckDB has no Postgres RowDescription OIDs.
