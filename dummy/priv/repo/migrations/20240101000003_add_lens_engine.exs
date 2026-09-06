defmodule Dummy.Repo.Migrations.AddLensEngine do
  use Ecto.Migration

  def up, do: PhoenixLens.Migrations.up()

  def down do
    execute("DROP TABLE IF EXISTS phoenix_lens_sources")
    execute("DROP TABLE IF EXISTS phoenix_lens_settings")
  end
end
