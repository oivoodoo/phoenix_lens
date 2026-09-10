# Field policy

Lens is designed so the **dashboard path** does not emit configured PII/PHI. It is not HIPAA or GDPR certified. You are the operator.

## What is protected

Merged, case-insensitive exact identifiers:

1. `config :phoenix_lens, masked_fields: [:email, :first_name, ...]`
2. `masked_fields_by_source` per database id
3. Every Ecto schema field with `redact: true` on the metadata repo's OTP app
4. Runtime rules from **Settings → Column protection**: global names, per source, and per table

`redact: true` on `User.email` also masks a result column named `email` on other tables. That is intentional in v1.

## How masking is applied

Every result goes through `PhoenixLens.Policy` before it leaves `PhoenixLens.Query`. There is no public unmasked run.

A column is masked when:

- the output name is protected (`SELECT email`), or
- the origin identifier is protected (`SELECT email AS contact`), or
- it is a computed expression whose SELECT item contains a protected identifier (`first_name || last_name`)

Masked cells are the atom `:redacted`, rendered `[redacted]`, including CSV, embeds, the audit viewer, **MCP tool results**, and **alert email/webhook payloads**.

`WHERE email = ...` is allowed. Quoted email/phone literals are redacted in stored SQL and in the audit log.

## Threat model (known limits)

- **IEx / `Repo.get`** — out of scope. This library polices the dashboard, not the BEAM.
- **Subquery smuggling** — `SELECT (SELECT email FROM users u2 WHERE u2.id = u.id)` may not resolve an origin. Treat as a reason to keep the mount admin-only.
- **EXPLAIN** — plan text can contain literals; it is still passed through the SQL redactor, not cell-level policy.
- **Result logging** — do not log `%PhoenixLens.Result{}` rows. The library does not.

## Query guards

Lens is **view-only**. User SQL cannot change application rows.

- One statement
- `SELECT` / `WITH` only (optional `EXPLAIN` of those)
- `DELETE`, `UPDATE`, `INSERT`, `MERGE`, `TRUNCATE`, writable CTEs, and `SELECT … FOR UPDATE` are rejected
- Postgres: `SET LOCAL transaction_read_only = on` so a slipped write still errors
- `statement_timeout` (default 5s)
- Hard row cap (default 10_000)
