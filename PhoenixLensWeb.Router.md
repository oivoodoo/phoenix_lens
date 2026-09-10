# `PhoenixLensWeb.Router`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.5/lib/phoenix_lens_web/router.ex#L1)

Router helper for mounting Lens in a Phoenix application.

    import PhoenixLensWeb.Router

    scope "/" do
      pipe_through [:browser, :require_admin]
      lens "/lens"
    end

# `lens`
*macro* 

---

*Consult [api-reference.md](api-reference.md) for complete listing*
