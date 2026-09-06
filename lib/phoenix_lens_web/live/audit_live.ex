defmodule PhoenixLensWeb.AuditLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Audit, Settings}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :audit)
     |> assign(:page_title, "Audit · Lens")
     |> assign(:audit_page, 1)
     |> assign(:per_page, 25)
     |> load()}
  end

  @impl true
  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, socket |> assign(:audit_page, to) |> load()}
  end

  def handle_event("page_size", %{"size" => size}, socket) do
    {:noreply, socket |> assign(:per_page, size) |> assign(:audit_page, 1) |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-browse">
      <header class="lens-browse-head">
        <div>
          <h1>Audit</h1>
          <p class="lens-muted">
            Who ran what. Redacted SQL, never result cells.
            Kept for {retention_copy(@retention_days)}.
            <a href={"#{@lens_prefix}/settings"}>Change in Settings</a>
          </p>
        </div>
      </header>
      <section class="lens-dash-card">
        <table class="lens-table">
          <thead>
            <tr>
              <th>When</th>
              <th>Actor</th>
              <th>SQL</th>
              <th>Rows</th>
              <th>ms</th>
              <th>Error</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@entries == []}>
              <td colspan="6" class="lens-muted">No audit rows yet.</td>
            </tr>
            <tr :for={row <- @entries}>
              <td class="lens-audit-when">{Audit.format_when(row["inserted_at"])}</td>
              <td>{row["actor"]}</td>
              <td>
                <code class="lens-audit-sql" title={row["sql_redacted"]}>{row["sql_redacted"]}</code>
              </td>
              <td>{row["row_count"]}</td>
              <td>{row["duration_ms"]}</td>
              <td>{row["error"]}</td>
            </tr>
          </tbody>
        </table>
        <div class="lens-pager">
          <span class="lens-muted">
            Showing {@from}–{@to} of {@total}
          </span>
          <div class="lens-pager-btns">
            <button
              type="button"
              class="ghost"
              disabled={@audit_page <= 1}
              phx-click="page"
              phx-value-to={@audit_page - 1}
            >
              Prev
            </button>
            <button
              type="button"
              class="ghost"
              disabled={@audit_page >= @pages}
              phx-click="page"
              phx-value-to={@audit_page + 1}
            >
              Next
            </button>
          </div>
          <form class="lens-chip" phx-change="page_size">
            Rows
            <select name="size">
              <option value="25" selected={@per_page == 25}>25</option>
              <option value="50" selected={@per_page == 50}>50</option>
              <option value="100" selected={@per_page == 100}>100</option>
            </select>
          </form>
        </div>
      </section>
    </div>
    """
  end

  defp load(socket) do
    page = Audit.page(socket.assigns.audit_page, socket.assigns.per_page)

    socket
    |> assign(:entries, page.entries)
    |> assign(:audit_page, page.page)
    |> assign(:pages, page.pages)
    |> assign(:total, page.total)
    |> assign(:per_page, page.per_page)
    |> assign(:from, page.from)
    |> assign(:to, page.to)
    |> assign(:retention_days, Settings.audit_retention_days())
  end

  defp retention_copy(0), do: "forever"
  defp retention_copy(days), do: "#{days} days"
end
