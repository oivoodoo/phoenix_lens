defmodule PhoenixLens.PolicyTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Policy

  @protected MapSet.new(["email", "first_name"])

  test "masks a column named email" do
    columns = [%{name: "email", origin: "email", computed?: false}]
    rows = [["alice@example.com"]]
    {_cols, rows, masked} = Policy.apply(columns, rows, @protected, "SELECT email FROM users")
    assert rows == [[:redacted]]
    assert masked == ["email"]
  end

  test "masks alias when origin is email" do
    columns = [%{name: "contact", origin: "email", computed?: false}]
    rows = [["alice@example.com"]]
    {_cols, rows, masked} = Policy.apply(columns, rows, @protected)

    assert rows == [[:redacted]]
    assert masked == ["contact"]
  end

  test "leaves unprotected columns intact" do
    columns = [%{name: "id", origin: "id", computed?: false}]
    rows = [[42]]
    {_cols, rows, masked} = Policy.apply(columns, rows, @protected)
    assert rows == [[42]]
    assert masked == []
  end

  test "does not mask email_hash unless listed" do
    columns = [%{name: "email_hash", origin: "email_hash", computed?: false}]
    rows = [["abc"]]
    {_cols, rows, _} = Policy.apply(columns, rows, @protected)
    assert rows == [["abc"]]
  end

  test "masks computed columns that reference first_name" do
    columns = [
      %{name: "name", origin: nil, computed?: true, sql: "first_name || last_name"}
    ]

    rows = [["Alice Smith"]]
    {_cols, rows, masked} = Policy.apply(columns, rows, @protected)
    assert rows == [[:redacted]]
    assert masked == ["name"]
  end

  test "does not mask count(*) just because WHERE mentions email" do
    columns = [%{name: "count", origin: nil, computed?: true, sql: "count(*)"}]
    rows = [[3]]
    sql = "SELECT count(*) FROM users WHERE email = 'alice@example.com'"
    {_cols, rows, masked} = Policy.apply(columns, rows, @protected, sql)
    assert rows == [[3]]
    assert masked == []
  end

  test "protected_set includes config fields" do
    config = %{
      masked_fields: [:phone],
      masked_fields_by_source: %{"analytics" => [:ip]},
      databases: %{}
    }

    assert MapSet.member?(Policy.protected_set(config), "phone")
    assert MapSet.member?(Policy.protected_set(config, "analytics"), "ip")
    refute MapSet.member?(Policy.protected_set(config, "primary"), "ip")
  end
end
