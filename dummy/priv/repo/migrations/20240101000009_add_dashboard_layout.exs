defmodule Dummy.Repo.Migrations.AddDashboardLayout do
  use Ecto.Migration

  def up, do: PhoenixLens.Migrations.up()
  def down, do: :ok
end
