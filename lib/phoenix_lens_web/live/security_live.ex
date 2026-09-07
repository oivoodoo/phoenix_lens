defmodule PhoenixLensWeb.SecurityLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.Auth
  alias PhoenixLensWeb.Hooks

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :settings)
     |> assign(:section, :security)
     |> assign(:page_title, "Security · Lens")
     |> assign(:form_error, nil)
     |> assign(:pending, nil)
     |> assign(:passkey_name, "This device")
     |> assign(:origin, nil)
     |> assign(:reg_challenge, nil)
     |> refresh()}
  end

  @impl true
  def handle_event("start_totp", _params, socket) do
    case Auth.start_totp() do
      {:ok, pending} ->
        {:noreply, socket |> assign(:pending, pending) |> assign(:form_error, nil) |> refresh()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  def handle_event("cancel_totp", _params, socket) do
    _ = Auth.cancel_totp_setup()
    {:noreply, socket |> assign(:pending, nil) |> refresh()}
  end

  def handle_event("confirm_totp", %{"code" => code}, socket) do
    case Auth.confirm_totp(code) do
      :ok ->
        prefix = socket.assigns.lens_prefix || "/lens"

        {:noreply,
         Hooks.unlock_redirect(socket,
           to: prefix <> "/settings/security",
           flash: "Authenticator enabled"
         )}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  def handle_event("disable_totp", %{"code" => code}, socket) do
    case Auth.disable_totp(code) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Authenticator disabled") |> refresh()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  def handle_event("passkey_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :passkey_name, name)}
  end

  def handle_event("passkey_origin", %{"origin" => origin}, socket) do
    {:noreply, assign(socket, :origin, Auth.origin_from(origin, fallback_origin(socket)))}
  end

  def handle_event("passkey_attestation", %{"error" => err}, socket)
      when is_binary(err) and err != "" do
    {:noreply, assign(socket, :form_error, err)}
  end

  def handle_event("start_passkey", params, socket) do
    name = params["name"] || socket.assigns.passkey_name
    origin = Auth.origin_from(params["origin"] || socket.assigns.origin, fallback_origin(socket))
    socket = socket |> assign(:passkey_name, name) |> assign(:origin, origin)
    challenge = Auth.registration_challenge(origin)
    exclude = Enum.map(socket.assigns.passkeys, & &1["credential_id"])

    {:noreply,
     socket
     |> assign(:reg_challenge, challenge)
     |> assign(:form_error, nil)
     |> push_event("passkey-register-options", %{
       challenge: Auth.challenge_bytes(challenge),
       rpId: Auth.rp_id(origin),
       rpName: "Lens",
       userId: Base.encode64("lens-operator-01"),
       userName: "operator",
       userDisplayName: "Lens operator",
       excludeCredentials: exclude
     })}
  end

  def handle_event("passkey_attestation", params, socket) do
    challenge = socket.assigns.reg_challenge

    if is_nil(challenge) do
      {:noreply, assign(socket, :form_error, "Passkey challenge expired. Try again.")}
    else
      case Auth.register_passkey(socket.assigns.passkey_name, params, challenge) do
        {:ok, _} ->
          prefix = socket.assigns.lens_prefix || "/lens"

          {:noreply,
           Hooks.unlock_redirect(socket,
             to: prefix <> "/settings/security",
             flash: "Passkey registered"
           )}

        {:error, error} ->
          {:noreply, assign(socket, :form_error, error.message)}
      end
    end
  end

  def handle_event("revoke_passkey", %{"id" => id}, socket) do
    case Auth.revoke_passkey(id) do
      :ok -> {:noreply, socket |> put_flash(:info, "Passkey removed") |> refresh()}
      {:error, error} -> {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-settings" id="lens-security" phx-hook="Passkey">
      <header class="lens-browse-head">
        <div>
          <p class="lens-kicker">Admin</p>
          <h1>Security</h1>
          <p class="lens-muted">
            Optional extra lock on the Lens UI. After you enable an authenticator app
            or a passkey, visitors must unlock at <code>/unlock</code>.
            MCP tokens skip this step. If you get locked out, run
            <code>PhoenixLens.Auth.reset!()</code>
            in IEx.
          </p>
        </div>
      </header>

      <PhoenixLensWeb.Components.SettingsNav.bar lens_prefix={@lens_prefix} section={@section} />

      <div :if={@form_error} class="lens-error">{@form_error}</div>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Authenticator app</h2>
        </header>
        <p class="lens-muted">
          TOTP from Google Authenticator, 1Password, Authy, and similar apps.
        </p>

        <%= if @totp_enabled do %>
          <p class="lens-status-pill is-ready" style="margin-top: 12px;">On</p>
          <form phx-submit="disable_totp" class="lens-protect-add" style="margin-top: 12px;">
            <input
              class="lens-field"
              type="text"
              name="code"
              placeholder="Current code"
              inputmode="numeric"
              autocomplete="one-time-code"
            />
            <button type="submit" class="ghost">Disable</button>
          </form>
        <% else %>
          <%= if @pending do %>
            <div class="lens-totp-setup">
              <div class="lens-qr">{Phoenix.HTML.raw(@pending.svg)}</div>
              <div>
                <p>Scan the QR code, then enter a 6-digit code to confirm.</p>
                <p class="lens-muted">Or type this secret: <code>{@pending.secret}</code></p>
                <form phx-submit="confirm_totp" class="lens-protect-add">
                  <input
                    class="lens-field"
                    type="text"
                    name="code"
                    placeholder="123456"
                    inputmode="numeric"
                    autocomplete="one-time-code"
                  />
                  <button type="submit">Confirm</button>
                  <button type="button" class="ghost" phx-click="cancel_totp">Cancel</button>
                </form>
              </div>
            </div>
          <% else %>
            <div class="lens-protect-add" style="margin-top: 12px;">
              <button type="button" phx-click="start_totp">Enable authenticator</button>
            </div>
          <% end %>
        <% end %>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Passkeys</h2>
        </header>
        <p class="lens-muted">
          Sign in with Touch ID, Face ID, Windows Hello, or a security key.
        </p>
        <form
          phx-change="passkey_name"
          phx-submit="start_passkey"
          class="lens-protect-add"
          style="margin-top: 12px;"
        >
          <input
            class="lens-field"
            type="text"
            name="name"
            value={@passkey_name}
            placeholder="This MacBook"
          />
          <button type="submit">Register passkey</button>
        </form>
        <table class="lens-table" style="margin-top: 16px;">
          <thead>
            <tr>
              <th>Name</th>
              <th>Added</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@passkeys == []}>
              <td colspan="3" class="lens-muted">No passkeys yet.</td>
            </tr>
            <tr :for={key <- @passkeys}>
              <td>{key["name"]}</td>
              <td class="lens-muted">{format_time(key["inserted_at"])}</td>
              <td>
                <button
                  type="button"
                  class="ghost tiny"
                  phx-click="revoke_passkey"
                  phx-value-id={key["id"]}
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  defp refresh(socket) do
    socket
    |> assign(:totp_enabled, Auth.totp_enabled?())
    |> assign(:passkeys, Auth.passkeys())
  end

  defp format_time(nil), do: ""
  defp format_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_time(other), do: to_string(other)

  defp fallback_origin(socket), do: socket.endpoint.url() |> String.trim_trailing("/")
end
