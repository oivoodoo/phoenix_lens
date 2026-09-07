# Changelog

## 0.1.3

- MCP server at `/lens/mcp` (Streamable HTTP JSON-RPC) covering catalog, SQL, questions, dashboards, audit, engines, sources, and column protection.
- Settings → MCP issues project token ids (`plt_…`) and one-time secrets (`lns_…`) for Bearer auth.
- Alerts on saved questions (rows / no rows / above / below) delivered by email (SMTP) and webhooks. Integrations live in Settings.
- Optional authenticator-app TOTP and passkey unlock in Settings → Security. MCP tokens skip the UI lock.

## 0.1.2

- Guide covering features, query design, DuckDB vs PostgreSQL, with dummy-app screenshots.
- Publish the guide and screenshots on HexDocs and GitHub Pages (`https://oivoodoo.github.io/phoenix_lens`).

## 0.1.1

- Notebook query builder, native SQL editor, Ctrl+Enter / Run, and in-place dashboard titles.
- Optional DuckDB engine: attach the host Repo as `repo` plus Postgres, MySQL, SQLite, DuckDB files, Parquet, CSV, and JSON; join them in one SELECT.
- Settings for engine, extra sources, audit retention, and a Column protection page (global, per source, per table).
- Audit log pagination and configurable retention (default 90 days).
- Charts (bar, line, pie, combo) with numeric/count axes; CSV/JSON export.
- Field policy tests for aliases, per-table rules, and `Query.run`.

## 0.1.0

- Initial release: SQL notebook, saved questions, dashboards, field policy, audit log.
