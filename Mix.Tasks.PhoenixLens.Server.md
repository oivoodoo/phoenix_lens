# `mix phoenix_lens.server`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.7/lib/mix/tasks/phoenix_lens.server.ex#L1)

Starts a standalone Lens dashboard.

    DATABASE_URL=postgres://user:pass@localhost/dbname mix phoenix_lens.server

First boot opens `/lens/setup` to create the operator login. `PORT` sets the
HTTP port (default 8080). Optional `HTTP_BASIC_USERNAME` / `HTTP_BASIC_PASSWORD`
enable HTTP basic auth. Optional `SMTP_HOST` + `SMTP_FROM` send an email
verification code and use it as 2FA.

Options:

    --port 8080

---

*Consult [api-reference.md](api-reference.md) for complete listing*
