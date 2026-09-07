# MCP

Lens exposes a [Model Context Protocol](https://modelcontextprotocol.io) server so agents can do the same work as the UI: run read-only SQL, save questions, pin dashboards, switch engines, and manage column protection. Field policy still masks every result.

## Mount

Add the plug **after** `Plug.Parsers` in the host endpoint. That keeps MCP out of the browser CSRF / `accepts: html` pipeline.

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Jason

plug PhoenixLensWeb.Plugs.MCP, path: "/lens/mcp"
```

The dummy app already does this. Open **Settings → MCP**.

## Project tokens

Each token has:

- **Token id** (`plt_…`) — public, listed in Settings
- **Secret** (`lns_…`) — shown once, stored as SHA-256

Send the secret on every request:

```
Authorization: Bearer lns_…
```

You can bind id and secret together: `Authorization: Bearer plt_…:lns_…`.

Revoking a token in Settings immediately rejects MCP clients that used it. Creating and revoking tokens is UI-only (a stolen MCP token cannot mint more tokens).

The optional Settings → Security lock (authenticator / passkey) applies to the notebook UI only. Bearer MCP calls are not asked for a second factor.

## Client config

```json
{
  "mcpServers": {
    "phoenix-lens": {
      "url": "http://localhost:4000/lens/mcp",
      "headers": {
        "Authorization": "Bearer lns_…"
      }
    }
  }
}
```

Replace the URL with your host (`https://app.example.com/lens/mcp`). Protocol: Streamable HTTP JSON-RPC (`initialize`, `tools/list`, `tools/call`).

## Tools

| Tool | UI equivalent |
| --- | --- |
| `list_tables`, `describe_table` | Data catalog |
| `run_sql`, `compile_notebook` | Ask (native SQL / notebook) |
| `list_questions`, `get_question`, `save_question`, `delete_question` | Questions |
| `export_csv`, `export_json` | Export |
| `list_dashboards`, `get_dashboard`, `save_dashboard`, `delete_dashboard` | Dashboards |
| `pin_question`, `unpin_card`, `run_dashboard` | Pin / open dashboard |
| `list_audit` | Audit |
| `get_settings`, `set_engine`, `set_audit_retention`, `reconnect_engine` | Settings → Engine |
| `add_source`, `remove_source` | Extra DuckDB sources |
| `list_protections`, `add_protection`, `remove_protection` | Column protection |
| `list_integrations`, `save_email_integration`, `add_webhook`, `remove_webhook` | Settings → Integrations |
| `list_alerts`, `create_alert`, `delete_alert`, `run_alert` | Question alerts |

`run_sql` is still SELECT/WITH only. Masked cells are `[redacted]` in tool output. Audit actor is `mcp:<token_id>`.
