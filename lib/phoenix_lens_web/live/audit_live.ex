defmodule PhoenixLensWeb.AuditLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.Audit

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :audit)
     |> assign(:page_title, "Audit · Lens")
     |> assign(:entries, Audit.recent())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-browse">
      <header class="lens-browse-head">
        <div>
          <h1>Audit</h1>
          <p class="lens-muted">Who ran what. Redacted SQL, never result cells.</p>
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
            <tr :for={row <- @entries}>
              <td>{row["inserted_at"]}</td>
              <td>{row["actor"]}</td>
              <td><code>{row["sql_redacted"]}</code></td>
              <td>{row["row_count"]}</td>
              <td>{row["duration_ms"]}</td>
              <td>{row["error"]}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end
end
