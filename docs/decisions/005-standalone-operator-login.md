# ADR-005: Standalone operator login (Docker only)

## Status
Accepted

## Date
2026-09-17

## Context
The library spec says Lens has no users table when mounted in a host Phoenix app. Docker standalone has no host pipeline. Operators need a first-boot account, optional email 2FA when SMTP is configured, and optional HTTP basic as an extra gate.

## Decision
Keep operator login **standalone-only** (`PhoenixLens.Standalone.enabled?/0`). Store one operator in `phoenix_lens_operators`. HTTP basic remains the existing Plug.BasicAuth env vars. Email 2FA uses the same SMTP channel as alerts.

Host mounts are unchanged: no setup/login, host `:require_admin` (or equivalent) is still the permission model.

## Alternatives considered
- Reuse TOTP/passkeys as the only lock: no username, and first boot would still need a password or a shared secret.
- Bake the operator into env vars: no first-boot prompt, and rotating credentials requires a restart.
- A full multi-user system: out of scope; standalone is a single operator dashboard.

## Consequences
- Docker image can be published and run with Postgres env vars only.
- First request to `/lens` redirects to `/setup` until an operator exists.
- SMTP is optional; without it, sign-in is username + password only.
