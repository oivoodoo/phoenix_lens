defmodule PhoenixLensWeb.MCPLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.Tokens

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :settings)
     |> assign(:section, :mcp)
     |> assign(:page_title, "MCP · Lens")
     |> assign(:new_name, "")
     |> assign(:form_error, nil)
     |> assign(:issued, nil)
     |> refresh()}
  end

  @impl true
  def handle_event("create", %{"name" => name}, socket) do
    case Tokens.create(name) do
      {:ok, issued} ->
        {:noreply,
         socket
         |> assign(:issued, issued)
         |> assign(:new_name, "")
         |> assign(:form_error, nil)
         |> put_flash(:info, "Token created. Copy the secret now — it will not be shown again.")
         |> refresh()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  def handle_event("dismiss_issued", _params, socket) do
    {:noreply, assign(socket, :issued, nil)}
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    case Tokens.revoke(id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:issued, nil)
         |> put_flash(:info, "Token revoked")
         |> refresh()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-settings">
      <header class="lens-browse-head">
        <div>
          <p class="lens-kicker">Admin</p>
          <h1>MCP</h1>
          <p class="lens-muted">
            Project tokens authenticate the MCP endpoint at <code>{@mcp_url}</code>.
            Agents can run SQL, save questions, pin dashboards, and change engines
            with the same field policy as the UI.
          </p>
        </div>
      </header>

      <PhoenixLensWeb.Components.SettingsNav.bar lens_prefix={@lens_prefix} section={@section} />

      <div :if={@form_error} class="lens-error">{@form_error}</div>

      <section :if={@issued} class="lens-dash-card lens-token-issued">
        <header class="lens-card-head">
          <h2>Copy this secret now</h2>
          <button type="button" class="ghost" phx-click="dismiss_issued">Done</button>
        </header>
        <p class="lens-muted">
          Token <strong>{@issued.name}</strong> will never show the secret again.
          Use the token id in MCP settings; send the secret as a Bearer token.
        </p>
        <dl class="lens-token-dl">
          <dt>Token id</dt>
          <dd><code>{@issued.token_id}</code></dd>
          <dt>Secret</dt>
          <dd><code class="lens-token-secret">{@issued.secret}</code></dd>
        </dl>
        <p class="lens-kicker">Cursor / Claude / HTTP MCP</p>
        <pre class="lens-nb-sql">{mcp_snippet(@mcp_url, @issued)}</pre>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>New token</h2>
        </header>
        <form phx-submit="create" class="lens-protect-add">
          <input
            class="lens-field"
            type="text"
            name="name"
            value={@new_name}
            placeholder="CI bot"
            autocomplete="off"
          />
          <button type="submit">Generate token</button>
        </form>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Active tokens</h2>
        </header>
        <table class="lens-table" style="margin-top: 12px;">
          <thead>
            <tr>
              <th>Name</th>
              <th>Token id</th>
              <th>Secret prefix</th>
              <th>Last used</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@tokens == []}>
              <td colspan="5" class="lens-muted">No project tokens yet.</td>
            </tr>
            <tr :for={row <- @tokens}>
              <td>{row["name"]}</td>
              <td><code>{row["token_id"]}</code></td>
              <td><code>{row["token_prefix"]}…</code></td>
              <td class="lens-muted">{format_time(row["last_used_at"])}</td>
              <td>
                <button
                  type="button"
                  class="ghost tiny"
                  phx-click="revoke"
                  phx-value-id={row["id"]}
                  data-confirm="Revoke this token? MCP clients using it will fail."
                >
                  Revoke
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
    |> assign(:tokens, Tokens.list())
    |> assign(:mcp_url, mcp_url(socket))
  end

  defp mcp_url(socket) do
    prefix = socket.assigns[:lens_prefix] || "/lens"
    base = socket.endpoint.url() |> String.trim_trailing("/")
    base <> prefix <> "/mcp"
  end

  defp mcp_snippet(url, issued) do
    """
    {
      "mcpServers": {
        "phoenix-lens": {
          "url": #{Jason.encode!(url)},
          "headers": {
            "Authorization": "Bearer #{issued.secret}"
          }
        }
      }
    }
    """
    |> String.trim()
  end

  defp format_time(nil), do: "never"

  defp format_time(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_time(other), do: to_string(other)
end
