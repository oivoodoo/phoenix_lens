defmodule PhoenixLensWeb.RouterMacroTest do
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

    :ok
  end

  test "unconfigured dashboard returns a 500" do
    Application.put_env(:phoenix_lens, :databases, %{})
    Application.delete_env(:phoenix_lens, :repo)
    Application.delete_env(:phoenix_lens, :url)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(PhoenixLens.TestEndpoint, :get, "/lens")

    assert conn.status == 500
    assert conn.resp_body =~ "PhoenixLens is not configured"
  end

  test "assets 404 for unknown files" do
    Application.put_env(:phoenix_lens, :repo, Foo.Repo)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(PhoenixLens.TestEndpoint, :get, "/lens/assets/nope.js")

    assert conn.status in [404, 500]
  end

  test "serves CSS under a nested Phoenix scope" do
    Application.put_env(:phoenix_lens, :repo, Foo.Repo)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(
        PhoenixLens.TestEndpoint,
        :get,
        "/dev/internal/lens/assets/application.css"
      )

    assert conn.status == 200
    assert conn.resp_body =~ ".lens-shell"
  end

  test "prefix_from_conn includes parent scopes" do
    conn = Phoenix.ConnTest.build_conn(:get, "/dev/internal/lens/assets/application.css")

    assert PhoenixLensWeb.Plugs.Dashboard.prefix_from_conn(conn, "/lens") ==
             "/dev/internal/lens"
  end
end
