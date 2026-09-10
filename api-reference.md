# phoenix_lens v0.1.5 - API Reference

## Modules

- [PhoenixLens](PhoenixLens.md): Mountable SQL notebook for Phoenix.
- [PhoenixLens.Alerts](PhoenixLens.Alerts.md): Saved-question alerts. Checked on a schedule; sent by email and/or webhook.

- [PhoenixLens.Auth](PhoenixLens.Auth.md): Optional Lens lock: authenticator-app TOTP and WebAuthn passkeys.
- [PhoenixLens.Components.QuestionCard](PhoenixLens.Components.QuestionCard.md): Embed a saved question in a host LiveView.
- [PhoenixLens.Dashboards](PhoenixLens.Dashboards.md): Dashboards of saved questions.

- [PhoenixLens.Integrations](PhoenixLens.Integrations.md): Email (SMTP) and webhook channels for alerts.

- [PhoenixLens.MCP](PhoenixLens.MCP.md): JSON-RPC 2.0 MCP server for Lens (Streamable HTTP).
- [PhoenixLens.Migrations](PhoenixLens.Migrations.md): Ecto migrations for questions, dashboards, and the audit log.
- [PhoenixLens.Protection](PhoenixLens.Protection.md): Runtime column protection: global, per source, and per table.
Additive to `config :phoenix_lens, masked_fields`.

- [PhoenixLens.Questions](PhoenixLens.Questions.md): Saved SQL questions in the host Repo.

- [PhoenixLens.Result](PhoenixLens.Result.md): A policy-applied query result. There is no unmasked variant.

- [PhoenixLens.Settings](PhoenixLens.Settings.md): Runtime query engine and extra DuckDB sources, stored on the host Repo.

- [PhoenixLens.Tokens](PhoenixLens.Tokens.md): Project tokens for the Lens MCP endpoint.
- [PhoenixLensWeb.AssetController](PhoenixLensWeb.AssetController.md)
- [PhoenixLensWeb.CSVController](PhoenixLensWeb.CSVController.md)
- [PhoenixLensWeb.Plugs.MCP](PhoenixLensWeb.Plugs.MCP.md): Streamable HTTP MCP endpoint.
- [PhoenixLensWeb.Router](PhoenixLensWeb.Router.md): Router helper for mounting Lens in a Phoenix application.

- Exceptions
  - [PhoenixLens.Error](PhoenixLens.Error.md): Error returned by `PhoenixLens.run/2`.

## Mix Tasks

- [mix phoenix_lens.server](Mix.Tasks.PhoenixLens.Server.md): Starts a standalone Lens dashboard.

