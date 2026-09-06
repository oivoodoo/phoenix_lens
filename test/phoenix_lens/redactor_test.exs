defmodule PhoenixLens.RedactorTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Redactor

  test "redacts emails in quoted SQL literals" do
    sql = "SELECT id FROM users WHERE email = 'alice@example.com'"
    assert Redactor.sql(sql) =~ "'[redacted]'"
    refute Redactor.sql(sql) =~ "alice@example.com"
  end

  test "redacts long digit runs in quotes" do
    sql = "SELECT 1 WHERE phone = '555-123-4567'"
    refute Redactor.sql(sql) =~ "555-123-4567"
  end

  test "actor never uses email from a user struct" do
    assert Redactor.actor(%{id: 7, email: "alice@example.com"}) == "user:7"
  end

  test "anonymous when nil" do
    assert Redactor.actor(nil) == "anonymous"
  end
end
