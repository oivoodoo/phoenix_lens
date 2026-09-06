defmodule PhoenixLens.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    if standalone?() and map_size(PhoenixLens.Config.get().databases) == 0 do
      IO.puts(:stderr, """
      PhoenixLens needs a database URL.

      Set DATABASE_URL, for example:

        DATABASE_URL=postgres://user:pass@localhost/dbname mix phoenix_lens.server
      """)

      System.halt(1)
    end

    children =
      connection_children() ++
        [{PhoenixLens.DuckDB.Server, []}] ++
        PhoenixLens.Standalone.children()

    opts = [strategy: :one_for_one, name: PhoenixLens.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp connection_children do
    if Application.get_env(:phoenix_lens, :start_connections, true) do
      PhoenixLens.Config.connection_children()
    else
      []
    end
  end

  defp standalone? do
    Application.get_env(:phoenix_lens, :standalone, false) == true or
      System.get_env("PHOENIX_LENS_SERVER") in ["1", "true"]
  end
end
