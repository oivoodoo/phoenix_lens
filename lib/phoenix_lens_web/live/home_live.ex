defmodule PhoenixLensWeb.HomeLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Catalog, Dashboards, Questions}

  @impl true
  def mount(_params, _session, socket) do
    schemas = Catalog.schemas()
    questions = Questions.list()
    dashboards = Dashboards.list()

    {:ok,
     socket
     |> assign(:page, :home)
     |> assign(:page_title, "Home · Lens")
     |> assign(:schemas, schemas)
     |> assign(:questions, questions)
     |> assign(:dashboards, dashboards)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-home">
      <div class="lens-home-hero">
        <p class="lens-kicker">Start here</p>
        <h1 class="lens-hello">Howdy, {greeting_name(@lens_actor)}</h1>
      </div>

      <section class="lens-home-pin" aria-label="Pinned dashboards">
        <div class="lens-home-pin-icon" aria-hidden="true">▦</div>
        <div>
          <h2>Your team's most important dashboards go here</h2>
          <p>
            Pin dashboards in <a href={"#{@lens_prefix}/dashboards"}>Our analytics</a>
            to have them appear in this space for everyone
          </p>
        </div>
      </section>

      <section class="lens-home-block">
        <p class="lens-kicker">Try these x-rays based on your data.</p>
        <div class="lens-xray-grid">
          <a
            :for={schema <- Enum.take(@schemas, 8)}
            class="lens-xray"
            href={"#{@lens_prefix}/ask?table=#{schema.source}"}
          >
            <span class="lens-xray-bolt" aria-hidden="true">⚡</span>
            <span>A look at your <strong>{humanize(schema.source)}</strong> table</span>
          </a>
          <%= if @schemas == [] do %>
            <a class="lens-xray" href={"#{@lens_prefix}/ask"}>
              <span class="lens-xray-bolt" aria-hidden="true">⚡</span>
              <span>Ask a question in SQL</span>
            </a>
            <a class="lens-xray" href={"#{@lens_prefix}/catalog"}>
              <span class="lens-xray-bolt" aria-hidden="true">⚡</span>
              <span>Browse the data catalog</span>
            </a>
          <% end %>
        </div>
      </section>

      <section class="lens-home-block">
        <p class="lens-kicker">Our analytics</p>
        <div class="lens-folder-grid">
          <a
            :for={dash <- @dashboards}
            class="lens-folder"
            href={"#{@lens_prefix}/dashboards/#{dash["id"]}"}
          >
            <span class="lens-folder-icon" aria-hidden="true">📁</span>
            {dash["name"]}
          </a>
          <a class="lens-folder" href={"#{@lens_prefix}/questions"}>
            <span class="lens-folder-icon" aria-hidden="true">📁</span> Questions
          </a>
          <a class="lens-folder" href={"#{@lens_prefix}/catalog"}>
            <span class="lens-folder-icon" aria-hidden="true">📁</span> Data
          </a>
          <a class="lens-folder" href={"#{@lens_prefix}/audit"}>
            <span class="lens-folder-icon" aria-hidden="true">📁</span> Audit
          </a>
        </div>
        <p class="lens-home-browse">
          <a href={"#{@lens_prefix}/dashboards"}>Browse all items →</a>
        </p>
      </section>

      <svg class="lens-scene" viewBox="0 0 960 180" aria-hidden="true">
        <path
          d="M0 140 C120 120 180 150 280 130 C380 110 420 150 520 135 C640 115 720 150 960 128 L960 180 L0 180 Z"
          fill="#E4F0FA"
        />
        <path d="M40 150 L80 90 L120 150" fill="none" stroke="#B9D8F0" stroke-width="2" />
        <path d="M200 150 L230 70 L260 150" fill="none" stroke="#B9D8F0" stroke-width="2" />
        <circle cx="720" cy="78" r="18" fill="none" stroke="#8DC7EC" stroke-width="2" />
        <path d="M720 96 L720 150 M700 110 L740 110" stroke="#8DC7EC" stroke-width="2" fill="none" />
        <path d="M780 150 C800 110 840 110 860 150" fill="none" stroke="#B9D8F0" stroke-width="2" />
        <path d="M820 150 C830 128 850 128 860 150" fill="none" stroke="#8DC7EC" stroke-width="2" />
      </svg>
    </div>
    """
  end

  defp humanize(source) when is_binary(source) do
    source
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize(_), do: "data"
end
