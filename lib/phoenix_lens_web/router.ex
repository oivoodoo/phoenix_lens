defmodule PhoenixLensWeb.Router do
  @moduledoc """
  Router helper for mounting Lens in a Phoenix application.

      import PhoenixLensWeb.Router

      scope "/" do
        pipe_through [:browser, :require_admin]
        lens "/lens"
      end
  """

  defmacro lens(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      import Phoenix.LiveView.Router

      mount_path = Phoenix.Router.scoped_path(__MODULE__, path)

      pipeline_name =
        mount_path
        |> String.trim("/")
        |> String.replace(~r/[^A-Za-z0-9_]/, "_")
        |> then(&:"phoenix_lens_#{&1}")

      session_name =
        mount_path
        |> String.trim("/")
        |> String.replace(~r/[^A-Za-z0-9_]/, "_")
        |> then(&:"phoenix_lens_session_#{&1}")

      pipeline pipeline_name do
        plug PhoenixLensWeb.Plugs.Dashboard, Keyword.put(opts, :mount_path, mount_path)
      end

      scope path, alias: false, as: false do
        pipe_through pipeline_name

        get "/assets/:file", PhoenixLensWeb.AssetController, :show
        get "/questions/:id/csv", PhoenixLensWeb.CSVController, :show
        get "/unlock/complete", PhoenixLensWeb.UnlockController, :complete
        post "/mcp", PhoenixLensWeb.Plugs.MCP, :rpc
        get "/mcp", PhoenixLensWeb.Plugs.MCP, :sse
        options "/mcp", PhoenixLensWeb.Plugs.MCP, :options

        live_session session_name,
          on_mount: PhoenixLensWeb.Hooks,
          session: {PhoenixLensWeb.Plugs.Dashboard, :session, []},
          root_layout: {PhoenixLensWeb.Layouts, :root} do
          live "/", PhoenixLensWeb.HomeLive, :index
          live "/unlock", PhoenixLensWeb.UnlockLive, :index
          live "/ask", PhoenixLensWeb.AskLive, :index
          live "/catalog", PhoenixLensWeb.CatalogLive, :index
          live "/questions", PhoenixLensWeb.QuestionLive, :index
          live "/questions/:id", PhoenixLensWeb.QuestionLive, :show
          live "/dashboards", PhoenixLensWeb.DashboardLive, :index
          live "/dashboards/:id", PhoenixLensWeb.DashboardLive, :show
          live "/audit", PhoenixLensWeb.AuditLive, :index
          live "/settings", PhoenixLensWeb.SettingsLive, :index
          live "/settings/protection", PhoenixLensWeb.ProtectionLive, :index
          live "/settings/mcp", PhoenixLensWeb.MCPLive, :index
          live "/settings/integrations", PhoenixLensWeb.IntegrationsLive, :index
          live "/settings/security", PhoenixLensWeb.SecurityLive, :index
        end
      end
    end
  end
end
