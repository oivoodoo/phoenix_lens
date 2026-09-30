defmodule Dummy.Repo.Migrations.UpgradePhoenixLens do
  use Ecto.Migration

  def up, do: PhoenixLens.Migrations.up()
  def down, do: :ok
end
