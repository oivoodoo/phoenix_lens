defmodule Mix.Tasks.PhoenixLens.Server do
  @moduledoc """
  Starts a standalone Lens dashboard.

      DATABASE_URL=postgres://user:pass@localhost/dbname mix phoenix_lens.server

  Options:

      --port 8080
  """
  use Mix.Task

  @shortdoc "Start a standalone PhoenixLens HTTP server"

  @impl true
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [port: :integer])

    if port = opts[:port] do
      System.put_env("PORT", Integer.to_string(port))
    end

    System.put_env("PHOENIX_LENS_SERVER", "true")
    PhoenixLens.Standalone.configure!()

    Mix.Task.run("app.start")

    Mix.shell().info(
      "Lens listening on http://localhost:#{System.get_env("PORT") || "8080"}/lens"
    )

    Process.sleep(:infinity)
  end
end
