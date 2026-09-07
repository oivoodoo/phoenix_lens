# Changelog

## 0.1.1

- Notebook query builder, native SQL editor, Ctrl+Enter / Run, and in-place dashboard titles.
- Optional DuckDB engine: attach the host Repo as `repo` plus Postgres, MySQL, SQLite, DuckDB files, Parquet, CSV, and JSON; join them in one SELECT.
- Settings for engine, extra sources, audit retention, and a Column protection page (global, per source, per table).
- Audit log pagination and configurable retention (default 90 days).
- Charts (bar, line, pie, combo) with numeric/count axes; CSV/JSON export.
- Field policy tests for aliases, per-table rules, and `Query.run`.

## 0.1.0

- Initial release: SQL notebook, saved questions, dashboards, field policy, audit log.
