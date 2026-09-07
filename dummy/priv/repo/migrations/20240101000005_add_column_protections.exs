defmodule Dummy.Repo.Migrations.AddColumnProtections do
  use Ecto.Migration

  def up, do: PhoenixLens.Migrations.up()

  def down do
    execute("DROP TABLE IF EXISTS phoenix_lens_protections")
  end
end
