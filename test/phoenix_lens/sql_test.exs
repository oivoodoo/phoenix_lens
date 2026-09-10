defmodule PhoenixLens.SQLTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.SQL

  test "accepts a single SELECT" do
    assert {:ok, "SELECT 1"} = SQL.validate("SELECT 1;")
  end

  test "accepts WITH" do
    assert {:ok, sql} = SQL.validate("WITH x AS (SELECT 1) SELECT * FROM x")
    assert sql =~ "WITH"
  end

  test "rejects empty SQL" do
    assert {:error, %{kind: :sql}} = SQL.validate("   ")
  end

  test "rejects multiple statements" do
    assert {:error, %{message: "one statement only"}} =
             SQL.validate("SELECT 1; SELECT 2")
  end

  test "rejects DELETE" do
    assert {:error, %{kind: :read_only, message: message}} = SQL.validate("DELETE FROM users")
    assert message =~ "view-only"
  end

  test "rejects UPDATE" do
    assert {:error, %{kind: :read_only, message: message}} =
             SQL.validate("UPDATE users SET name = 'x'")

    assert message =~ "view-only"
  end

  test "rejects UPDATE with a leading comment" do
    assert {:error, %{kind: :read_only}} =
             SQL.validate("-- nbd\nUPDATE users SET name = 'x'")
  end

  test "rejects writable CTE DELETE" do
    assert {:error, %{kind: :read_only}} =
             SQL.validate("WITH t AS (DELETE FROM users RETURNING id) SELECT * FROM t")
  end

  test "rejects writable CTE UPDATE" do
    assert {:error, %{kind: :read_only}} =
             SQL.validate("WITH t AS (UPDATE users SET name = 'x' RETURNING id) SELECT * FROM t")
  end

  test "rejects SELECT FOR UPDATE" do
    assert {:error, %{kind: :read_only}} = SQL.validate("SELECT * FROM users FOR UPDATE")
  end

  test "rejects MERGE" do
    assert {:error, %{kind: :read_only}} =
             SQL.validate(
               "MERGE INTO users t USING src s ON t.id = s.id WHEN MATCHED THEN DELETE"
             )
  end

  test "rejects TRUNCATE" do
    assert {:error, %{kind: :read_only}} = SQL.validate("TRUNCATE users")
  end

  test "rejects ATTACH" do
    assert {:error, %{kind: :read_only}} = SQL.validate("ATTACH 'other.db' AS warehouse")
  end

  test "rejects INSERT" do
    assert {:error, %{kind: :read_only}} = SQL.validate("INSERT INTO users VALUES (1)")
  end

  test "rejects SELECT INTO" do
    assert {:error, %{kind: :read_only}} = SQL.validate("SELECT * INTO tmp FROM users")
  end

  test "does not treat 'updates' as UPDATE" do
    assert {:ok, _} = SQL.validate("SELECT * FROM updates")
  end

  test "does not treat last_updated as UPDATE" do
    assert {:ok, _} = SQL.validate("SELECT last_updated FROM users")
  end

  test "strips comments before classifying" do
    assert {:ok, _} = SQL.validate("-- delete everything\nSELECT 1")
  end

  test "table_refs reads FROM and JOIN" do
    refs = SQL.table_refs("SELECT * FROM users u JOIN repo.orders o ON o.user_id = u.id")
    assert %{source: nil, table: "users"} in refs
    assert %{source: "repo", table: "orders"} in refs
  end

  test "table_refs keeps quoted identifiers" do
    assert [%{table: "comments"}] = SQL.table_refs(~s[SELECT * FROM "comments" LIMIT 100])
  end

  test "describe_item extracts alias origin" do
    assert {"contact", "email", false} = SQL.describe_item("email AS contact")
    assert {"email", "email", false} = SQL.describe_item("users.email")
    assert {"name", nil, true} = SQL.describe_item("first_name || last_name AS name")
  end

  test "column_origins maps alias back to email" do
    cols =
      SQL.column_origins("SELECT id, email AS contact FROM users", ["id", "contact"])

    assert Enum.at(cols, 1).origin == "email"
    assert Enum.at(cols, 0).origin == "id"
  end
end
