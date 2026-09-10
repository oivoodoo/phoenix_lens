# `PhoenixLensWeb.Plugs.MCP`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.5/lib/phoenix_lens_web/plugs/mcp.ex#L1)

Streamable HTTP MCP endpoint.

Put this **after** `Plug.Parsers` in the host endpoint so it runs before the
browser pipeline (CSRF / `accepts: html`):

    plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
    plug PhoenixLensWeb.Plugs.MCP, path: "/lens/mcp"

Authenticate with `Authorization: Bearer <secret>` from Settings → MCP.

# `call`

# `init`

# `options`

# `rpc`

# `sse`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
