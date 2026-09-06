defmodule Dummy.Repo.Migrations.AddAuditRetention do
  use Ecto.Migration

  def up, do: PhoenixLens.Migrations.up()

  def down do
    execute("ALTER TABLE phoenix_lens_settings DROP COLUMN IF EXISTS audit_retention_days")
  end
end
