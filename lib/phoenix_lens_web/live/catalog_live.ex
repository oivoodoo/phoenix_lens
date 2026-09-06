defmodule PhoenixLensWeb.CatalogLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.Catalog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :catalog)
     |> assign(:page_title, "Data · Lens")
     |> assign(:schemas, Catalog.schemas())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-browse">
      <header class="lens-browse-head">
        <div>
          <h1>Data</h1>
          <p class="lens-muted">
            Ecto schemas from the host app. Protected fields never appear in query outputs.
          </p>
        </div>
      </header>

      <%= if @schemas == [] do %>
        <p class="lens-empty">No Ecto schemas found on the configured repo.</p>
      <% end %>

      <div class="lens-xray-grid">
        <a
          :for={schema <- @schemas}
          class="lens-xray"
          href={"#{@lens_prefix}/ask?table=#{schema.source}"}
        >
          <span class="lens-xray-bolt" aria-hidden="true">⚡</span>
          <span>A look at your <strong>{schema.source}</strong> table</span>
        </a>
      </div>

      <section :for={schema <- @schemas} class="lens-dash-card">
        <header class="lens-card-head">
          <h2>{schema.source} <span class="lens-muted">{schema.module}</span></h2>
          <a href={"#{@lens_prefix}/ask?table=#{schema.source}"}>Ask →</a>
        </header>
        <table class="lens-table">
          <thead>
            <tr>
              <th>Field</th>
              <th>Type</th>
              <th>Protected</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={field <- schema.fields}>
              <td class={if field.protected, do: "masked"}>{field.name}</td>
              <td>{field.type}</td>
              <td>{if field.protected, do: "yes", else: ""}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end
end
