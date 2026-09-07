defmodule PhoenixLens.ProtectionTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.{Policy, Protection, SQL}

  @empty %{global: MapSet.new(), sources: %{}, tables: %{}}
  @config %{masked_fields: [:phone], masked_fields_by_source: %{}, databases: %{}}

  setup do
    previous = :persistent_term.get({Protection, :rules}, :miss)
    :persistent_term.put({Protection, :rules}, @empty)

    on_exit(fn ->
      :persistent_term.put({Protection, :rules}, previous)
    end)

    :ok
  end

  test "normalize global column" do
    assert {:ok, row} = Protection.normalize(%{scope: "global", column: "Email"})
    assert row == %{scope: "global", source_id: nil, table_name: nil, column_name: "email"}
  end

  test "normalize source column" do
    assert {:ok, row} =
             Protection.normalize(%{scope: "source", source_id: "Warehouse", column: "IP"})

    assert row.scope == "source"
    assert row.source_id == "warehouse"
    assert row.column_name == "ip"
    assert row.table_name == nil
  end

  test "normalize table column" do
    assert {:ok, row} =
             Protection.normalize(%{
               scope: "table",
               source_id: "primary",
               table: "Users",
               column: "badge_id"
             })

    assert row == %{
             scope: "table",
             source_id: "primary",
             table_name: "users",
             column_name: "badge_id"
           }
  end

  test "normalize requires source and table for table scope" do
    assert {:error, _} = Protection.normalize(%{scope: "table", column: "email"})
  end

  test "normalize rejects invalid column identifiers" do
    assert {:error, %{message: message}} =
             Protection.normalize(%{scope: "global", column: "a;drop"})

    assert message =~ "identifier"
  end

  test "column_protected? respects global, source, and table" do
    put_rules(%{
      global: MapSet.new(["ssn"]),
      sources: %{"billing" => MapSet.new(["account_no"])},
      tables: %{{"primary", "users"} => MapSet.new(["badge_id"])}
    })

    assert Protection.column_protected?("SSN")
    assert Protection.column_protected?("account_no", "billing")
    refute Protection.column_protected?("account_no", "primary")
    assert Protection.column_protected?("badge_id", "primary", "users")
    refute Protection.column_protected?("badge_id", "primary", "posts")
  end

  test "names_for_sql applies table rules from FROM/JOIN" do
    put_rules(%{
      global: MapSet.new(),
      sources: %{},
      tables: %{
        {"primary", "users"} => MapSet.new(["email"]),
        {"primary", "posts"} => MapSet.new(["title"])
      }
    })

    user_sql = Protection.names_for_sql("primary", "SELECT email, id FROM users")
    assert MapSet.member?(user_sql, "email")
    refute MapSet.member?(user_sql, "title")

    post_sql = Protection.names_for_sql("primary", ~s[SELECT title FROM "posts"])
    assert MapSet.member?(post_sql, "title")
    refute MapSet.member?(post_sql, "email")
  end

  test "policy merges runtime global, source, and table rules" do
    put_rules(%{
      global: MapSet.new(["ssn"]),
      sources: %{"warehouse" => MapSet.new(["ip"])},
      tables: %{{"primary", "users"} => MapSet.new(["badge_id"])}
    })

    assert MapSet.member?(Policy.protected_set(@config), "phone")
    assert MapSet.member?(Policy.protected_set(@config), "ssn")
    refute MapSet.member?(Policy.protected_set(@config, "primary"), "ip")
    assert MapSet.member?(Policy.protected_set(@config, "warehouse"), "ip")

    users =
      Policy.protected_set(@config, "primary", tables: [%{source: "primary", table: "users"}])

    assert MapSet.member?(users, "badge_id")

    refute MapSet.member?(
             Policy.protected_set(@config, "primary", tables: [%{table: "posts"}]),
             "badge_id"
           )
  end

  test "apply masks table-protected columns when SQL references that table" do
    put_rules(%{
      global: MapSet.new(),
      sources: %{},
      tables: %{{"primary", "users"} => MapSet.new(["email"])}
    })

    sql = "SELECT id, email AS contact FROM users"
    protected = Policy.protected_set(@config, "primary", sql: sql)

    columns = [
      %{name: "id", origin: "id", computed?: false},
      %{name: "contact", origin: "email", computed?: false}
    ]

    {_cols, rows, masked} =
      Policy.apply(columns, [[1, "alice@example.com"]], protected, sql)

    assert rows == [[1, :redacted]]
    assert "contact" in masked
  end

  test "apply does not mask the same column name on an unprotected table" do
    put_rules(%{
      global: MapSet.new(),
      sources: %{},
      tables: %{{"primary", "users"} => MapSet.new(["email"])}
    })

    sql = "SELECT email FROM subscriptions"
    protected = Policy.protected_set(@config, "primary", sql: sql)

    columns = [%{name: "email", origin: "email", computed?: false}]
    {_cols, rows, masked} = Policy.apply(columns, [["a@b.com"]], protected, sql)
    assert rows == [["a@b.com"]]
    assert masked == []
  end

  test "apply masks computed expressions that use a protected attribute" do
    put_rules(%{
      global: MapSet.new(["first_name"]),
      sources: %{},
      tables: %{}
    })

    protected = Policy.protected_set(%{@config | masked_fields: []}, "primary")

    columns = [
      %{name: "full_name", origin: nil, computed?: true, sql: "first_name || last_name"}
    ]

    {_cols, rows, masked} = Policy.apply(columns, [["Ada Lovelace"]], protected)
    assert rows == [[:redacted]]
    assert masked == ["full_name"]
  end

  test "source protection does not leak to another source" do
    put_rules(%{
      global: MapSet.new(),
      sources: %{"analytics" => MapSet.new(["ip"])},
      tables: %{}
    })

    primary = Policy.protected_set(%{@config | masked_fields: []}, "primary")
    analytics = Policy.protected_set(%{@config | masked_fields: []}, "analytics")
    refute MapSet.member?(primary, "ip")
    assert MapSet.member?(analytics, "ip")
  end

  test "SQL table_refs feed names_for_sql for joins" do
    put_rules(%{
      global: MapSet.new(),
      sources: %{},
      tables: %{
        {"repo", "users"} => MapSet.new(["email"]),
        {"primary", "orders"} => MapSet.new(["sku"])
      }
    })

    sql = "SELECT u.email, o.sku FROM repo.users u JOIN orders o ON o.user_id = u.id"
    assert %{source: "repo", table: "users"} in SQL.table_refs(sql)
    names = Protection.names_for_sql("primary", sql)
    assert MapSet.member?(names, "email")
    assert MapSet.member?(names, "sku")
  end

  defp put_rules(rules), do: :persistent_term.put({Protection, :rules}, rules)
end
