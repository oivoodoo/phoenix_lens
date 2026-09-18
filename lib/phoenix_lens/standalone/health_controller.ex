defmodule PhoenixLens.Standalone.HealthController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  def index(conn, _params) do
    case ping() do
      :ok ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, "ok")

      :error ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(503, "db")
    end
  end

  defp ping do
    case PhoenixLens.Standalone.Repo.query("SELECT 1", []) do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end
end
