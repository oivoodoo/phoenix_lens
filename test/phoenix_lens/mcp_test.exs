defmodule PhoenixLens.MCPTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.MCP
  alias PhoenixLens.MCP.Tools
  alias PhoenixLens.Tokens

  test "initialize advertises tools and a protocol version" do
    {:reply, resp} =
      MCP.handle(
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => "2025-03-26"}
        },
        %{actor: %{id: "plt_test", kind: :mcp, name: "test"}}
      )

    assert resp["id"] == 1
    assert resp["result"]["protocolVersion"] == "2025-03-26"
    assert resp["result"]["capabilities"]["tools"] == %{}
    assert resp["result"]["serverInfo"]["name"] == "phoenix-lens"
  end

  test "unknown method is JSON-RPC -32601" do
    {:reply, resp} =
      MCP.handle(
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "nope"},
        %{actor: %{id: "plt_test", kind: :mcp}}
      )

    assert resp["error"]["code"] == -32601
  end

  test "initialized notification has no reply" do
    assert :noreply =
             MCP.handle(
               %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
               %{actor: %{}}
             )
  end

  test "tools/list includes run_sql and save_question" do
    names = Enum.map(Tools.list(), & &1["name"])
    assert "run_sql" in names
    assert "save_question" in names
    assert "pin_question" in names
    assert "layout_dashboard" in names
    assert "set_engine" in names
    assert "add_protection" in names
    assert "create_alert" in names
    assert "add_webhook" in names
  end

  test "parse_bearer accepts secret and token_id:secret" do
    assert {:ok, nil, "lns_abc"} = Tokens.parse_bearer("Bearer lns_abc")
    assert {:ok, "plt_1", "lns_abc"} = Tokens.parse_bearer("plt_1:lns_abc")
    assert :error = Tokens.parse_bearer("")
  end

  test "compile_notebook produces SQL" do
    {:ok, value} =
      Tools.call(
        "compile_notebook",
        %{
          "table" => "orders",
          "aggregations" => [%{"fun" => "count"}],
          "breakouts" => ["status"],
          "limit" => 10
        },
        %{actor: %{id: "plt_test", kind: :mcp}}
      )

    assert value["sql"] =~ ~r/FROM "orders"/
    assert value["sql"] =~ "count(*)"
    assert value["sql"] =~ "GROUP BY"
  end
end
