defmodule PhoenixLensWeb.IntegrationsLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Alerts, Integrations}
  alias PhoenixLens.Alerts.Mailer

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :settings)
     |> assign(:section, :integrations)
     |> assign(:page_title, "Integrations · Lens")
     |> assign(:form_error, nil)
     |> assign(:hook_error, nil)
     |> assign(:new_hook_name, "")
     |> assign(:new_hook_url, "")
     |> assign(:new_hook_auth, "none")
     |> assign(:new_hook_token, "")
     |> refresh()}
  end

  @impl true
  def handle_event("save_email", params, socket) do
    case Integrations.save_email(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:form_error, nil)
         |> put_flash(:info, "Email integration saved")
         |> refresh()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  def handle_event("add_webhook", params, socket) do
    case Integrations.add_webhook(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:hook_error, nil)
         |> assign(:new_hook_name, "")
         |> assign(:new_hook_url, "")
         |> assign(:new_hook_auth, "none")
         |> assign(:new_hook_token, "")
         |> put_flash(:info, "Webhook added")
         |> refresh()}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:new_hook_name, params["name"] || "")
         |> assign(:new_hook_url, params["url"] || "")
         |> assign(:new_hook_auth, params["auth"] || "none")
         |> assign(:new_hook_token, params["token"] || "")
         |> assign(:hook_error, error.message)}
    end
  end

  def handle_event("remove_webhook", %{"id" => id}, socket) do
    case Integrations.delete(id) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Webhook removed") |> refresh()}

      {:error, error} ->
        {:noreply, assign(socket, :hook_error, error.message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-settings">
      <header class="lens-browse-head">
        <div>
          <p class="lens-kicker">Admin</p>
          <h1>Integrations</h1>
          <p class="lens-muted">
            Configure email (SMTP) and webhooks, then attach them to alerts on saved questions.
            Alert payloads are field-policy masked.
          </p>
        </div>
      </header>

      <PhoenixLensWeb.Components.SettingsNav.bar lens_prefix={@lens_prefix} section={@section} />

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Email</h2>
        </header>
        <p class="lens-muted">
          One SMTP channel for the instance. Alerts pick recipients per question.
        </p>
        <p :if={!@mailer?} class="lens-error-inline" style="margin-top: 8px;">
          {Mailer.missing_message()}
        </p>
        <div :if={@form_error} class="lens-error">{@form_error}</div>
        <form phx-submit="save_email" class="lens-modal-form" style="padding: 12px 0 0;">
          <label>
            Host
            <input
              class="lens-field"
              type="text"
              name="host"
              value={@email_cfg["host"]}
              placeholder="smtp.example.com"
            />
          </label>
          <label>
            Port
            <input class="lens-field" type="number" name="port" value={@email_cfg["port"] || 587} />
          </label>
          <label>
            From
            <input
              class="lens-field"
              type="email"
              name="from"
              value={@email_cfg["from"]}
              placeholder="lens@example.com"
            />
          </label>
          <label>
            Username
            <input
              class="lens-field"
              type="text"
              name="username"
              value={@email_cfg["username"]}
              autocomplete="off"
            />
          </label>
          <label>
            Password
            <input
              class="lens-field"
              type="password"
              name="password"
              placeholder={if @email_cfg["has_password"], do: "••••••••", else: ""}
              autocomplete="new-password"
            />
          </label>
          <label class="lens-check">
            <input type="checkbox" name="tls" value="true" checked={@email_cfg["tls"] != false} />
            Use TLS
          </label>
          <div class="lens-modal-actions">
            <button type="submit">Save SMTP</button>
          </div>
        </form>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Webhooks</h2>
        </header>
        <p class="lens-muted">
          Named HTTP endpoints. Alerts POST JSON (question name, masked rows) to the URL.
        </p>
        <div :if={@hook_error} class="lens-error">{@hook_error}</div>
        <table class="lens-table" style="margin-top: 12px;">
          <thead>
            <tr>
              <th>Name</th>
              <th>URL</th>
              <th>Auth</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@webhooks == []}>
              <td colspan="4" class="lens-muted">No webhooks yet.</td>
            </tr>
            <tr :for={hook <- @webhooks}>
              <td>{hook["name"]}</td>
              <td><code>{get_in(hook, ["config", "url"])}</code></td>
              <td class="lens-muted">{get_in(hook, ["config", "auth"]) || "none"}</td>
              <td>
                <button
                  type="button"
                  class="ghost tiny"
                  phx-click="remove_webhook"
                  phx-value-id={hook["id"]}
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <form phx-submit="add_webhook" class="lens-modal-form" style="padding: 16px 0 0;">
          <label>
            Name
            <input
              class="lens-field"
              type="text"
              name="name"
              value={@new_hook_name}
              placeholder="Pager"
            />
          </label>
          <label>
            URL
            <input
              class="lens-field"
              type="url"
              name="url"
              value={@new_hook_url}
              placeholder="https://example.com/hooks/lens"
            />
          </label>
          <label>
            Auth
            <select class="lens-field" name="auth">
              <option value="none" selected={@new_hook_auth == "none"}>None</option>
              <option value="bearer" selected={@new_hook_auth == "bearer"}>Bearer token</option>
              <option value="header" selected={@new_hook_auth == "header"}>API key header</option>
            </select>
          </label>
          <label>
            Token / API key
            <input
              class="lens-field"
              type="password"
              name="token"
              value={@new_hook_token}
              autocomplete="off"
            />
          </label>
          <div class="lens-modal-actions">
            <button type="submit">Add webhook</button>
          </div>
        </form>
      </section>
    </div>
    """
  end

  defp refresh(socket) do
    email = Integrations.email()
    cfg = (email && Integrations.public(email)["config"]) || %{}

    socket
    |> assign(:email_cfg, cfg)
    |> assign(:webhooks, Enum.map(Integrations.list("webhook"), &Integrations.public/1))
    |> assign(:mailer?, Mailer.available?())
    |> assign(:alert_count, length(Alerts.list()))
  end
end
