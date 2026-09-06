defmodule PhoenixLensWeb.AssetController do
  use PhoenixLensWeb, :controller

  plug :skip_csrf

  defp skip_csrf(conn, _opts) do
    Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)
  end

  @assets %{
    "application.css" => "text/css",
    "application.js" => "text/javascript",
    "phoenix.js" => "text/javascript",
    "phoenix_live_view.js" => "text/javascript"
  }

  def show(conn, %{"file" => file}) do
    case Map.get(@assets, file) do
      nil ->
        send_resp(conn, 404, "Not found")

      content_type ->
        path = Application.app_dir(:phoenix_lens, "priv/static/#{file}")

        if File.exists?(path) do
          conn
          |> put_resp_content_type(content_type)
          |> put_resp_header("cache-control", "public, max-age=86400")
          |> send_file(200, path)
        else
          send_resp(conn, 404, "Not found")
        end
    end
  end
end
