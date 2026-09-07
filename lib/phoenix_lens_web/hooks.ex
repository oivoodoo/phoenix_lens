defmodule PhoenixLensWeb.Hooks do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, session, socket) do
    prefix = session["lens_prefix"] || "/lens"
    unlocked? = session["lens_unlocked"] == true or session[:lens_unlocked] == true

    socket =
      socket
      |> assign(:lens_prefix, prefix)
      |> assign(:lens_actor, session["lens_actor"])
      |> assign(:lens_databases, session["lens_databases"] || [])
      |> assign(:page, :home)
      |> assign(:page_title, "Lens")

    if PhoenixLens.Auth.required?() and not unlocked? and socket.view != PhoenixLensWeb.UnlockLive do
      {:halt, redirect(socket, to: prefix <> "/unlock")}
    else
      {:cont, socket}
    end
  end

  def unlock_redirect(socket, opts \\ []) do
    prefix = socket.assigns[:lens_prefix] || "/lens"
    to = Keyword.get(opts, :to, prefix)
    flash = Keyword.get(opts, :flash)
    ticket = PhoenixLens.Auth.issue_unlock_ticket(to: to, flash: flash)
    redirect(socket, to: prefix <> "/unlock/complete?t=" <> URI.encode_www_form(ticket))
  end
end
