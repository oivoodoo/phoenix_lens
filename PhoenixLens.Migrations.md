# `PhoenixLens.Migrations`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.8/lib/phoenix_lens/migrations.ex#L1)

Ecto migrations for questions, dashboards, and the audit log.

    defmodule MyApp.Repo.Migrations.AddPhoenixLens do
      use Ecto.Migration

      def up, do: PhoenixLens.Migrations.up()
      def down, do: PhoenixLens.Migrations.down()
    end

Upgrading an existing 0.1.x database: add another migration and call `up/0`
again. It is idempotent. Missing columns are added only when
`information_schema` says they are absent, so a database that already has
them does not take `ACCESS EXCLUSIVE`.

    defmodule MyApp.Repo.Migrations.UpgradePhoenixLens do
      use Ecto.Migration

      def up, do: PhoenixLens.Migrations.up()
      def down, do: :ok
    end

# `down`

# `ensure_all`

Creates any missing Lens tables and columns.

Successful runs are remembered for this node. Request paths should call
`ensure_once/1`, which backs off after a failure instead of repeating DDL.

# `ensure_once`

Runs `ensure_all/1` at most once per node. A failed attempt waits 60000ms
before trying again, so a dashboard request cannot queue DDL on every card.

# `statements`

# `up`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
