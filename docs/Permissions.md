# Permissions

Lens has no users table. The host Phoenix pipeline is the permission model, same as PgHero.

```elixir
pipeline :require_admin do
  plug :browser
  plug MyAppWeb.Plugs.RequireAdmin
end

scope "/" do
  pipe_through :require_admin
  lens "/lens"
end
```

Audit `actor` is `conn.assigns[:current_user]` (configurable via `actor_assign:`). A struct with `:id` is stored as `user:<id>` — never the email.

The MCP server is a second entry point, not a second permission model. Mount `PhoenixLensWeb.Plugs.MCP` on the same host, issue project tokens in **Settings → MCP**, and treat those tokens like admin credentials. MCP audit rows use `mcp:<token_id>`. A stolen token cannot mint more tokens. See [MCP.md](MCP.md).

Optional **Settings → Security** (authenticator app and passkeys) is an extra lock on the LiveView UI after the host pipeline has already let the operator in. MCP tokens skip it. `PhoenixLens.Auth.reset!/0` clears enrollment from IEx if you lose the factor.

Prefer a Postgres role that can `SELECT` but not `INSERT`/`UPDATE`/`DELETE` on application tables, and point Lens at a replica:

```elixir
config :phoenix_lens,
  repo: MyApp.Repo,
  databases: [
    analytics: [url: System.get_env("ANALYTICS_DATABASE_URL"), name: "Analytics"]
  ]
```

The replica user is a complement to application-layer masking, not a replacement. Masking still runs so aliases cannot leak configured fields through the UI.
