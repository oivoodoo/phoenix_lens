defmodule PhoenixLensWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html],
        layouts: [html: PhoenixLensWeb.Layouts]

      import Plug.Conn
      import PhoenixLensWeb.Helpers
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0]
      import PhoenixLensWeb.Helpers
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {PhoenixLensWeb.Layouts, :app}

      import PhoenixLensWeb.Helpers
      alias PhoenixLensWeb.Components.ResultTable
      alias PhoenixLensWeb.Components.SqlEditor
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
