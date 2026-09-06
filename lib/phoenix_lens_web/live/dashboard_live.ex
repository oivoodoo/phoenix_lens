defmodule PhoenixLensWeb.DashboardLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Dashboards, Policy, Query}

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    case Dashboards.get(id) do
      {:ok, dashboard} ->
        from = params["from"]
        to = params["to"]
        cards = Enum.map(dashboard["cards"], &run_card(&1, from, to, socket))

        {:ok,
         socket
         |> assign(:page, :dashboards)
         |> assign(:page_title, "#{dashboard["name"]} · Lens")
         |> assign(:dashboard, dashboard)
         |> assign(:cards, cards)
         |> assign(:from, from)
         |> assign(:to, to)}

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page, :dashboards)
         |> assign(:dashboard, nil)
         |> put_flash(:error, error.message)}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :dashboards)
     |> assign(:page_title, "Dashboards · Lens")
     |> assign(:dashboards, Dashboards.list())
     |> assign(:dashboard, :index)
     |> assign(:name, "")}
  end

  @impl true
  def handle_event("create", %{"name" => name}, socket) do
    case Dashboards.save(%{name: name}) do
      {:ok, dash} ->
        {:noreply, push_navigate(socket, to: lens_path(socket, "/dashboards/#{dash["id"]}"))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  def handle_event("delete", _params, socket) do
    Dashboards.delete(socket.assigns.dashboard["id"])
    {:noreply, push_navigate(socket, to: lens_path(socket, "/dashboards"))}
  end

  def handle_event("unpin", %{"id" => id}, socket) do
    Dashboards.remove_card(id)
    {:ok, dashboard} = Dashboards.get(socket.assigns.dashboard["id"])

    cards =
      Enum.map(dashboard["cards"], &run_card(&1, socket.assigns.from, socket.assigns.to, socket))

    {:noreply, socket |> assign(:dashboard, dashboard) |> assign(:cards, cards)}
  end

  @impl true
  def render(%{dashboard: :index} = assigns) do
    ~H"""
    <div class="lens-browse">
      <header class="lens-browse-head">
        <h1>Dashboards</h1>
        <form phx-submit="create" class="lens-inline">
          <input
            class="lens-field"
            type="text"
            name="name"
            placeholder="New dashboard"
            value={@name}
            autocomplete="off"
          />
          <button type="submit">Create</button>
        </form>
      </header>
      <div class="lens-folder-grid">
        <a
          :for={d <- @dashboards}
          class="lens-folder"
          href={"#{@lens_prefix}/dashboards/#{d["id"]}"}
        >
          <span class="lens-folder-icon" aria-hidden="true">📁</span>
          {d["name"]}
        </a>
      </div>
      <p :if={@dashboards == []} class="lens-empty">
        No dashboards yet. Create one, then pin questions onto it.
      </p>
    </div>
    """
  end

  def render(%{dashboard: nil} = assigns) do
    ~H"""
    <h1>Dashboard</h1>
    <p>Not found.</p>
    """
  end

  def render(assigns) do
    ~H"""
    <article class="lens-dash">
      <header class="lens-dash-head">
        <div>
          <p class="lens-kicker">Dashboard</p>
          <h1>{@dashboard["name"]}</h1>
        </div>
        <button type="button" class="ghost" phx-click="delete" data-confirm="Delete this dashboard?">
          Delete
        </button>
      </header>

      <form method="get" class="lens-filter-row">
        <label class="lens-chip">
          Date range <input type="date" name="from" value={@from} />
        </label>
        <label class="lens-chip">
          to <input type="date" name="to" value={@to} />
        </label>
        <button type="submit" class="ghost">Apply</button>
      </form>

      <%= if @cards == [] do %>
        <p class="lens-empty">No cards yet. Save a question and pin it here.</p>
      <% end %>

      <div class="lens-dash-grid">
        <section :for={card <- @cards} class="lens-dash-card">
          <header class="lens-card-head">
            <a href={"#{@lens_prefix}/questions/#{card.question_id}"}>{card.name}</a>
            <button type="button" class="ghost tiny" phx-click="unpin" phx-value-id={card.id}>
              ···
            </button>
          </header>
          <%= if card.error do %>
            <p class="lens-error">{card.error.message}</p>
          <% else %>
            <ResultTable.visualization result={card.result} viz={card.viz} />
          <% end %>
        </section>
      </div>
    </article>
    """
  end

  defp run_card(card, from, to, socket) do
    sql = card["sql"]
    date_column = card["date_column"]
    protected = Policy.protected_set(PhoenixLens.Config.get(), card["database_id"])

    sql =
      if is_binary(date_column) and date_column != "" and
           not MapSet.member?(protected, String.downcase(date_column)) do
        Dashboards.wrap_date_filter(sql, date_column, from, to)
      else
        sql
      end

    {result, error} =
      case Query.run(sql,
             database: card["database_id"],
             actor: socket.assigns.lens_actor,
             question_id: card["question_id"]
           ) do
        {:ok, result} -> {result, nil}
        {:error, error} -> {nil, error}
      end

    %{
      id: card["id"],
      question_id: card["question_id"],
      name: card["question_name"],
      viz: card["viz"],
      result: result,
      error: error
    }
  end
end
