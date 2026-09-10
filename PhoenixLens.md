# `PhoenixLens`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.5/lib/phoenix_lens.ex#L1)

Mountable SQL notebook for Phoenix.

Point it at your Ecto repo, save questions, pin dashboards, and mask PII/PHI
in every result sink.

    config :phoenix_lens,
      repo: MyApp.Repo,
      masked_fields: [:email, :first_name, :phone]

    import PhoenixLensWeb.Router

    scope "/" do
      pipe_through [:browser, :require_admin]
      lens "/lens"
    end

# `config`

# `databases`

# `run`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
