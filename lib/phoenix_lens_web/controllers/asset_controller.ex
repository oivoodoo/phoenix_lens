defmodule PhoenixLensWeb.AssetController do
  use PhoenixLensWeb, :controller

  plug :skip_csrf

  defp skip_csrf(conn, _opts) do
    Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)
  end

  @mime %{
    "application.css" => "text/css",
    "application.js" => "text/javascript",
    "phoenix.js" => "text/javascript",
    "phoenix_live_view.js" => "text/javascript"
  }

  def show(conn, %{"file" => file}) do
    case Map.get(@mime, file) do
      nil ->
        send_resp(conn, 404, "Not found")

      content_type ->
        case asset_path(file) do
          nil ->
            send_resp(conn, 404, "Not found")

          path ->
            conn
            |> put_resp_content_type(content_type)
            |> put_resp_header("cache-control", "no-cache")
            |> send_file(200, path)
        end
    end
  end

  # Serve phoenix/live_view JS from the host app so the protocol matches the
  # LiveView version that compiled Lens templates. Vendoring 1.2 JS into a 1.0
  # host makes HEEx comprehensions render as "undefined".
  defp asset_path("phoenix.js") do
    first_existing([
      app_static(:phoenix, "phoenix.js"),
      app_static(:phoenix_lens, "phoenix.js")
    ])
  end

  defp asset_path("phoenix_live_view.js") do
    first_existing([
      app_static(:phoenix_live_view, "phoenix_live_view.js"),
      app_static(:phoenix_live_view, "phoenix_live_view.min.js"),
      app_static(:phoenix_lens, "phoenix_live_view.js")
    ])
  end

  defp asset_path(file), do: first_existing([app_static(:phoenix_lens, file)])

  defp app_static(app, file) do
    Path.join(Application.app_dir(app, "priv/static"), file)
  rescue
    ArgumentError -> nil
  end

  defp first_existing(paths) do
    Enum.find(paths, fn
      path when is_binary(path) -> File.exists?(path)
      _ -> false
    end)
  end
end
