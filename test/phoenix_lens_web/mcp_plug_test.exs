defmodule PhoenixLensWeb.MCPPlugTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.get_all_env(:phoenix_lens)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_lens),
          do: Application.delete_env(:phoenix_lens, key)

      for {key, value} <- previous, do: Application.put_env(:phoenix_lens, key, value)
    end)

    unless Process.whereis(PhoenixLens.TestPubSub) do
      start_supervised!({Phoenix.PubSub, name: PhoenixLens.TestPubSub})
    end

    unless Process.whereis(PhoenixLens.TestEndpoint) do
      start_supervised!(PhoenixLens.TestEndpoint)
    end

    Application.put_env(:phoenix_lens, :repo, Foo.Repo)
    :ok
  end

  test "POST /lens/mcp without a token is 401" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(
        PhoenixLens.TestEndpoint,
        :post,
        "/lens/mcp",
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{}
        })
      )

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] =~ "token"
  end

  test "POST /lens/mcp with a junk token is 401" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("authorization", "Bearer lns_not-real")
      |> Phoenix.ConnTest.dispatch(
        PhoenixLens.TestEndpoint,
        :post,
        "/lens/mcp",
        Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})
      )

    assert conn.status == 401
  end

  test "OPTIONS /lens/mcp is 204" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(PhoenixLens.TestEndpoint, :options, "/lens/mcp")

    assert conn.status == 204
  end
end
