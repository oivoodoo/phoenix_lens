defmodule PhoenixLensWeb.Hooks do
  @moduledoc false

  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:lens_prefix, session["lens_prefix"] || "/lens")
     |> assign(:lens_actor, session["lens_actor"])
     |> assign(:lens_databases, session["lens_databases"] || [])
     |> assign(:page, :home)
     |> assign(:page_title, "Lens")}
  end
end
