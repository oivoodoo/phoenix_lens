defmodule Dummy.Repo.Migrations.AddMcpTokens do
  use Ecto.Migration

  def up, do: PhoenixLens.Migrations.up()
  def down, do: :ok
end
