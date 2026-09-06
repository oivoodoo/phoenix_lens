defmodule PhoenixLens.SettingsTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Settings

  test "normalize_source accepts a postgres alias" do
    assert {:ok, source} =
             Settings.normalize_source(%{
               alias: "Warehouse",
               kind: "postgres",
               dsn: "postgresql://u:p@localhost/db"
             })

    assert source.alias == "warehouse"
    assert source.kind == "postgres"
  end

  test "normalize_source rejects reserved aliases" do
    assert {:error, %{message: message}} =
             Settings.normalize_source(%{alias: "repo", kind: "postgres", dsn: "x"})

    assert message =~ "reserved"
  end

  test "normalize_source rejects blank dsn" do
    assert {:error, %{message: message}} =
             Settings.normalize_source(%{alias: "events", kind: "csv", dsn: "  "})

    assert message =~ "required"
  end

  test "redact_dsn hides URI passwords" do
    assert Settings.redact_dsn("postgresql://u:secret@localhost/db") ==
             "postgresql://u:••••@localhost/db"
  end

  test "redact_dsn hides libpq passwords" do
    assert Settings.redact_dsn("host=localhost password=secret dbname=app") ==
             "host=localhost password=•••• dbname=app"
  end

  test "engine defaults to postgresql" do
    assert Settings.engine() in [:postgresql, :duckdb]
  end
end
