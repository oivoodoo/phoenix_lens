# `PhoenixLens.Result`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.7/lib/phoenix_lens/result.ex#L1)

A policy-applied query result. There is no unmasked variant.

# `t`

```elixir
@type t() :: %PhoenixLens.Result{
  columns: [String.t()],
  database_id: String.t(),
  duration_ms: non_neg_integer(),
  masked_columns: [String.t()],
  num_rows: non_neg_integer(),
  rows: [[term()]],
  sql: String.t() | nil,
  truncated: boolean()
}
```

# `display_cell`

# `redacted_label`

# `sanitize`

Make every cell Jason-safe so LiveView can push results over the socket.

Postgrex returns uuid/bytea as raw binaries; those crash `Jason.encode!/1`.

# `sanitize_cell`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
