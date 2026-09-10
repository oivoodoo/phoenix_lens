# `PhoenixLens.Error`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.5/lib/phoenix_lens/error.ex#L1)

Error returned by `PhoenixLens.run/2`.

# `t`

```elixir
@type t() :: %PhoenixLens.Error{
  __exception__: true,
  kind: :sql | :policy | :timeout | :read_only | :config,
  message: String.t()
}
```

# `from_exception`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
