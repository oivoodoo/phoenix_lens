# `PhoenixLens.Migrations`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.7/lib/phoenix_lens/migrations.ex#L1)

Ecto migrations for questions, dashboards, and the audit log.

    defmodule MyApp.Repo.Migrations.AddPhoenixLens do
      use Ecto.Migration

      def up, do: PhoenixLens.Migrations.up()
      def down, do: PhoenixLens.Migrations.down()
    end

# `down`

# `ensure_all`

# `statements`

# `up`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
