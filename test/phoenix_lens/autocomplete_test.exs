defmodule PhoenixLens.AutocompleteTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Autocomplete

  @catalog [
    %{
      name: "users",
      columns: [
        %{name: "id", protected: false, type: "id"},
        %{name: "email", protected: true, type: "string"},
        %{name: "first_name", protected: true, type: "string"}
      ]
    },
    %{
      name: "posts",
      columns: [
        %{name: "id", protected: false, type: "id"},
        %{name: "title", protected: false, type: "string"},
        %{name: "user_id", protected: false, type: "id"}
      ]
    }
  ]

  test "suggests tables after FROM" do
    sql = "SELECT id FROM us"
    items = Autocomplete.suggest(@catalog, sql, String.length(sql))
    assert Enum.any?(items, &(&1.value == "users" and &1.kind == "table"))
    refute Enum.any?(items, &(&1.kind == "column"))
  end

  test "suggests tables after JOIN" do
    sql = "SELECT * FROM users JOIN p"
    items = Autocomplete.suggest(@catalog, sql, String.length(sql))
    assert Enum.map(items, & &1.value) == ["posts"]
  end

  test "suggests columns of a table after a dotted prefix" do
    sql = "SELECT users.em"
    items = Autocomplete.suggest(@catalog, sql, String.length(sql))
    assert Enum.map(items, & &1.value) == ["email"]
    assert hd(items).kind == "column"
  end

  test "suggests columns in SELECT lists" do
    sql = "SELECT tit"
    items = Autocomplete.suggest(@catalog, sql, String.length(sql))
    assert Enum.any?(items, &(&1.value == "title" and &1.kind == "column"))
  end

  test "marks protected columns" do
    sql = "SELECT em"
    items = Autocomplete.suggest(@catalog, sql, String.length(sql))
    email = Enum.find(items, &(&1.value == "email"))
    assert email.protected
    assert email.detail =~ "redacted"
  end

  test "suggests SQL keywords" do
    sql = "SEL"
    items = Autocomplete.suggest(@catalog, sql, String.length(sql))
    assert Enum.any?(items, &(&1.value == "SELECT" and &1.kind == "keyword"))
  end

  test "empty prefix after FROM lists tables" do
    sql = "SELECT * FROM "
    items = Autocomplete.suggest(@catalog, sql, String.length(sql))
    names = Enum.map(items, & &1.value)
    assert "users" in names
    assert "posts" in names
  end

  test "payload/1 includes tables from schema maps" do
    payload = Autocomplete.payload(@catalog)
    assert %{tables: tables, keywords: keywords} = payload
    assert Enum.any?(tables, &(&1.name == "users"))
    assert "SELECT" in keywords
  end
end
