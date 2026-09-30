defmodule PhoenixLens.MigrationsTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.{Audit, Dashboards, Settings}

  test "upgrade column SQL checks information_schema before altering" do
    for sql <- [Dashboards.layout_alter_sql(), Settings.settings_alter_sql()] do
      assert sql =~ "information_schema.columns"
      assert sql =~ "ADD COLUMN"
      refute sql =~ "ADD COLUMN IF NOT EXISTS"
    end
  end

  test "audit purge is a bounded delete" do
    sql = Audit.purge_statement()
    assert sql =~ "LIMIT 1000"
    assert sql =~ "WHERE id IN"
  end
end
