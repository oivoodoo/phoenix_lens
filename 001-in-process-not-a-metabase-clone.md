# ADR-001: In-process PgHero-shaped library, not a Metabase clone

## Status
Accepted

## Date
2026-09-04

## Context
Phoenix teams run Metabase (or similar) as a sidecar to ask questions of app data. That sidecar is a second JVM, a second auth system, a second DB user with broad SELECT, and a second processor under GDPR. The temptation is to reimplement Metabase in Elixir.

Metabase is a decade of Clojure + React: GUI query builder, MBQL, collections, embeddings, drivers. A Hex library that tries to match that surface will not ship. PgHero-Elixir already proved the mountable-engine pattern in this workspace.

## Decision
Build `phoenix_lens` as a mountable Phoenix library that uses the host Ecto Repo (and optional replica URL), mounted behind the host auth pipeline. v1 is a SQL notebook with saved questions, a simple dashboard, and a field policy. We will not clone Metabase’s query builder, permission system, or driver architecture.

## Alternatives Considered

### Full Metabase-in-Elixir
- Pros: Feature-complete replacement story
- Cons: Multi-year product company, not a Hex library; would still talk to Postgres as a dumb SQL client
- Rejected: Scope. PgHero shipped because it did one job.

### Code-first questions only (Elixir modules in git)
- Pros: Best audit trail, compile-time PII checks
- Cons: Does not replace ad-hoc Metabase SQL; high friction for “just run this”
- Rejected for v1: Keep as a later export path (`mix phoenix_lens.export`).

### Schema-only explorer, no SQL
- Pros: Strongest PHI control
- Cons: The user is a Phoenix developer who lives in SQL; they would keep Metabase
- Rejected for v1: SQL is the job. Schema catalog is a helper, not the only interface.

## Consequences
- Install story matches PgHero: `mix deps.get`, config repo, `lens "/lens"` behind `:require_admin`
- Durable differentiation is in-process (auth plug, Ecto `redact: true`, LiveView embed, Oban later) plus field policy
- We will be compared to Metabase on GUI features and will lose that comparison on purpose
- Host app remains the identity provider; Lens has no users table
