# ADR-002: Field policy on every result sink, not HTML-only masking

## Status
Accepted

## Date
2026-09-04

## Context
GDPR (minimization, privacy by design, records of processing) and healthcare (HIPAA minimum necessary, audit controls) require that PII/PHI not leak through analytics. The requested control is a plugin setting listing fields to mask (`email`, `first_name`, …).

Name-based masking of the result grid is bypassable (`SELECT email AS contact`, `first_name || last_name`, CSV export, exception logs, alert emails). A library that claims “healthcare acceptable” while only starring columns in HTML would fail the first review.

A Hex library cannot be “HIPAA certified.” The operator is the covered entity. We can be designed so that the dashboard path does not emit protected values.

## Decision
1. **Control plane:** merge `masked_fields` config, per-database overrides, and every Ecto schema field with `redact: true`.
2. **Enforcement:** one `PhoenixLens.Policy` function runs on every sink — LiveView grid, CSV, JSON, chart tooltips, embeds, logs, future alerts. There is no unmasked result type that UI code is allowed to hold.
3. **Alias hole:** resolve origin columns via PostgreSQL `RowDescription` (table OID + attribute number → `pg_attribute.attname`). Mask if the origin name **or** the output alias is protected.
4. **Expressions:** if a result column has no origin (computed), treat it as protected when the SELECT item’s SQL text contains a protected identifier. Known limitation: subquery/function smuggling. Document it; do not claim it is closed.
5. **WHERE:** protected fields may appear in filters (support lookup). Literals that look like emails/phones in stored SQL and the audit viewer are redacted.
6. **Default render:** the atom `:redacted` displayed as `[redacted]`. Not hashed, not dropped, in v1.
7. **Never persist rowsets.** Persist questions and audit metadata only. Audit stores redacted SQL, query hash, actor, row count, duration — never cells.

## Alternatives Considered

### Display-only mask (config list → star columns in the table)
- Pros: Fast
- Cons: Aliases, CSV, logs, and emails bypass it
- Rejected: Incompatible with the healthcare requirement.

### Allowlist / deny querying PHI at all
- Pros: What auditors actually want
- Cons: Breaks `WHERE email = $1` support lookups; heavier SQL analysis
- Deferred: `strict: true` is an explicit v2 flag, not the v1 default.

### Strip columns instead of mask
- Pros: Cleaner CSV
- Cons: User asked for mask; stripping hides that a column was selected (confusing while writing SQL)
- Deferred: optional `on_protected: :strip | :mask | :hash` after mask works.

### Database views / column privileges as the only control
- Pros: Enforced by Postgres
- Cons: Host apps do not want a parallel schema; Ecto `redact: true` is already the semantic layer
- Rejected as the only control; operators may still use a restricted DB user on a replica, and we should document that.

## Consequences
- Policy is a pure function of `{columns, rows, policy}` → `{columns, rows}` and is unit-tested without Phoenix
- SQL execution must keep origin metadata, not just aliased names
- Logger backends and exception pages must go through the same redactor
- Subquery bypass remains a documented threat; mount stays admin-only
- “Designed for GDPR/HIPAA” language in the README; no certification claim
