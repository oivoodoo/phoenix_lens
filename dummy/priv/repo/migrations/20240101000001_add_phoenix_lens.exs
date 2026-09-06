defmodule Dummy.Repo.Migrations.AddPhoenixLens do
  use Ecto.Migration

  def up, do: PhoenixLens.Migrations.up()
  def down, do: PhoenixLens.Migrations.down()
end
