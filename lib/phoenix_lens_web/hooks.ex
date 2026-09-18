defmodule PhoenixLensWeb.Hooks do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, session, socket) do
    prefix = session["lens_prefix"] || "/lens"
    unlocked? = session["lens_unlocked"] == true or session[:lens_unlocked] == true
    operator = session["lens_operator"]
    gate? = socket.view in [PhoenixLensWeb.SetupLive, PhoenixLensWeb.LoginLive]

    socket =
      socket
      |> assign(:lens_prefix, prefix)
      |> assign(:lens_actor, session["lens_actor"])
      |> assign(:lens_databases, session["lens_databases"] || [])
      |> assign(:lens_standalone, session["lens_standalone"] == true)
      |> assign(:lens_operator, operator)
      |> assign(:page, :home)
      |> assign(:page_title, "Lens")

    cond do
      gate? ->
        {:cont, socket}

      PhoenixLens.Operator.required?() and is_nil(operator) and
          not PhoenixLens.Operator.configured?() ->
        {:halt, redirect(socket, to: prefix <> "/setup")}

      PhoenixLens.Operator.required?() and is_nil(operator) ->
        {:halt, redirect(socket, to: prefix <> "/login")}

      PhoenixLens.Auth.required?() and not unlocked? and socket.view != PhoenixLensWeb.UnlockLive ->
        {:halt, redirect(socket, to: prefix <> "/unlock")}

      true ->
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
