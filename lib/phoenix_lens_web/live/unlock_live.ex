defmodule PhoenixLensWeb.UnlockLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.Auth
  alias PhoenixLensWeb.Hooks

  @impl true
  def mount(_params, session, socket) do
    prefix = socket.assigns[:lens_prefix] || session["lens_prefix"] || "/lens"
    unlocked? = session["lens_unlocked"] == true or session[:lens_unlocked] == true

    cond do
      not Auth.required?() or unlocked? ->
        {:ok, redirect(socket, to: prefix)}

      true ->
        {:ok,
         socket
         |> assign(:page, :unlock)
         |> assign(:page_title, "Unlock · Lens")
         |> assign(:error, nil)
         |> assign(:origin, nil)
         |> assign(:totp?, Auth.totp_enabled?())
         |> assign(:passkeys?, Auth.passkeys() != [])
         |> assign(:challenge, nil)}
    end
  end

  @impl true
  def handle_event("passkey_origin", %{"origin" => origin}, socket) do
    origin = Auth.origin_from(origin, fallback_origin(socket))
    socket = assign(socket, :origin, origin)

    if socket.assigns.passkeys? do
      {:noreply, start_passkey(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("verify_totp", %{"code" => code}, socket) do
    if Auth.verify_totp(code) do
      {:noreply, unlock(socket)}
    else
      {:noreply, assign(socket, :error, "That authenticator code is not valid")}
    end
  end

  def handle_event("passkey_assert", %{"error" => err}, socket)
      when is_binary(err) and err != "" do
    {:noreply, assign(socket, :error, err)}
  end

  def handle_event("passkey_assert", params, socket) do
    challenge = socket.assigns.challenge

    if is_nil(challenge) do
      {:noreply, assign(socket, :error, "Passkey challenge expired. Refresh and try again.")}
    else
      case Auth.authenticate_passkey(params, challenge) do
        :ok -> {:noreply, unlock(socket)}
        {:error, error} -> {:noreply, assign(socket, :error, error.message)}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-unlock">
      <div class="lens-dash-card">
        <p class="lens-kicker">Lens lock</p>
        <h1>Unlock Lens</h1>
        <p class="lens-muted">
          Authenticator or a passkey is required before opening the notebook.
        </p>

        <div :if={@error} class="lens-error">{@error}</div>

        <form :if={@totp?} phx-submit="verify_totp" class="lens-modal-form" style="padding: 16px 0 0;">
          <label>
            Authenticator code
            <input
              class="lens-field"
              type="text"
              name="code"
              inputmode="numeric"
              autocomplete="one-time-code"
              placeholder="123456"
              maxlength="8"
            />
          </label>
          <div class="lens-modal-actions">
            <button type="submit">Verify</button>
          </div>
        </form>

        <div :if={@passkeys?} id="lens-passkey-unlock" phx-hook="Passkey" class="lens-passkey-block">
          <button type="button" data-passkey-assert>Sign in with passkey</button>
        </div>
      </div>
    </div>
    """
  end

  defp start_passkey(socket) do
    origin = socket.assigns.origin || fallback_origin(socket)
    challenge = Auth.authentication_challenge(origin)
    allow = Enum.map(Auth.passkeys(), & &1["credential_id"])

    socket
    |> assign(:challenge, challenge)
    |> push_event("passkey-assert-options", %{
      challenge: Auth.challenge_bytes(challenge),
      rpId: Auth.rp_id(origin),
      allowCredentials: allow
    })
  end

  defp unlock(socket), do: Hooks.unlock_redirect(socket)

  defp fallback_origin(socket), do: socket.endpoint.url() |> String.trim_trailing("/")
end
