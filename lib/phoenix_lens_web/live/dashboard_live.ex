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
         |> assign(:name, dashboard["name"])
         |> assign(:cards, cards)
         |> assign(:from, from)
         |> assign(:to, to)
         |> assign(:editing, false)
         |> assign(:layout_snapshot, nil)}

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
     |> assign(:dashboard, :index)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    case Dashboards.save(%{name: default_name(socket.assigns.dashboards)}) do
      {:ok, dash} ->
        {:noreply, push_navigate(socket, to: lens_path(socket, "/dashboards/#{dash["id"]}"))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  def handle_event("rename", %{"name" => name}, socket) do
    name = blank_to_default(name)

    case Dashboards.save(%{id: socket.assigns.dashboard["id"], name: name}) do
      {:ok, dash} ->
        {:noreply,
         socket
         |> assign(:dashboard, Map.put(socket.assigns.dashboard, "name", dash["name"]))
         |> assign(:name, dash["name"])
         |> assign(:page_title, "#{dash["name"]} · Lens")}

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
      if socket.assigns[:editing] do
        Enum.reject(socket.assigns.cards, &(to_string(&1.id) == to_string(id)))
      else
        Enum.map(
          dashboard["cards"],
          &run_card(&1, socket.assigns.from, socket.assigns.to, socket)
        )
      end

    {:noreply, socket |> assign(:dashboard, dashboard) |> assign(:cards, cards)}
  end

  def handle_event("edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:layout_snapshot, Enum.map(socket.assigns.cards, &layout_tuple/1))}
  end

  def handle_event("cancel_edit", _params, socket) do
    cards = restore_layout(socket.assigns.cards, socket.assigns.layout_snapshot)

    {:noreply,
     socket
     |> assign(:editing, false)
     |> assign(:layout_snapshot, nil)
     |> assign(:cards, cards)}
  end

  def handle_event("save_layout", _params, socket) do
    items =
      Enum.map(socket.assigns.cards, fn card ->
        %{
          "id" => card.id,
          "col" => card.col,
          "row" => card.row,
          "size_x" => card.size_x,
          "size_y" => card.size_y
        }
      end)

    case Dashboards.save_layout(socket.assigns.dashboard["id"], items) do
      {:ok, dashboard} ->
        cards = apply_saved_layout(socket.assigns.cards, dashboard["cards"])

        {:noreply,
         socket
         |> assign(:editing, false)
         |> assign(:layout_snapshot, nil)
         |> assign(:dashboard, dashboard)
         |> assign(:cards, cards)
         |> put_flash(:info, "Dashboard layout saved")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  def handle_event("place_card", params, socket) do
    if socket.assigns[:editing] do
      layout = Dashboards.clamp_layout(params)
      id = to_string(params["id"] || params[:id])

      cards =
        Enum.map(socket.assigns.cards, fn card ->
          if to_string(card.id) == id do
            %{
              card
              | col: layout["col"],
                row: layout["row"],
                size_x: layout["size_x"],
                size_y: layout["size_y"]
            }
          else
            card
          end
        end)

      {:noreply, assign(socket, :cards, cards)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(%{dashboard: :index} = assigns) do
    ~H"""
    <div class="lens-browse">
      <header class="lens-browse-head">
        <h1>Dashboards</h1>
        <button type="button" phx-click="create">New dashboard</button>
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
        <form phx-change="rename" phx-submit="rename" class="lens-title-form">
          <input
            class="lens-title-input"
            type="text"
            name="name"
            value={@name}
            placeholder="New dashboard"
            autocomplete="off"
            phx-debounce="blur"
          />
        </form>
        <div class="lens-dash-actions">
          <%= if @editing do %>
            <button type="button" class="ghost" phx-click="cancel_edit">Cancel</button>
            <button type="button" phx-click="save_layout">Save</button>
          <% else %>
            <button type="button" class="ghost" phx-click="edit">Edit</button>
            <button
              type="button"
              class="ghost"
              phx-click="delete"
              data-confirm="Delete this dashboard?"
            >
              Delete
            </button>
          <% end %>
        </div>
      </header>

      <form method="get" class="lens-filter-bar" aria-label="Dashboard filters">
        <p class="lens-filter-kicker">Date range</p>
        <div class="lens-filter-fields">
          <label class="lens-filter-field">
            <span>From</span>
            <input type="date" name="from" value={@from} />
          </label>
          <span class="lens-filter-sep" aria-hidden="true">→</span>
          <label class="lens-filter-field">
            <span>To</span>
            <input type="date" name="to" value={@to} />
          </label>
          <button type="submit">Apply</button>
        </div>
      </form>

      <%= if @cards == [] do %>
        <p class="lens-empty">No cards yet. Save a question and pin it here.</p>
      <% end %>

      <div
        id={"lens-dash-board-#{@dashboard["id"]}"}
        class={["lens-dash-board", @editing && "is-editing"]}
        phx-hook="DashBoard"
        data-cols={Dashboards.cols()}
        data-editing={to_string(@editing)}
      >
        <section
          :for={card <- @cards}
          id={"dash-card-#{card.id}"}
          class="lens-dash-card"
          data-id={card.id}
          data-col={card.col}
          data-row={card.row}
          data-sx={card.size_x}
          data-sy={card.size_y}
          style={"grid-column: #{card.col + 1} / span #{card.size_x}; grid-row: #{card.row + 1} / span #{card.size_y}"}
        >
          <header class="lens-card-head" data-dash-drag={@editing && "true"}>
            <a :if={!@editing} href={"#{@lens_prefix}/questions/#{card.question_id}"}>{card.name}</a>
            <span :if={@editing} class="lens-dash-card-title">{card.name}</span>
            <button
              :if={@editing}
              type="button"
              class="ghost tiny"
              phx-click="unpin"
              phx-value-id={card.id}
            >
              Remove
            </button>
          </header>
          <div class="lens-dash-card-body">
            <%= if card.error do %>
              <p class="lens-error">{card.error.message}</p>
            <% else %>
              <ResultTable.visualization result={card.result} viz={card.viz} />
            <% end %>
          </div>
          <button
            :if={@editing}
            type="button"
            class="lens-dash-resize"
            data-dash-resize
            aria-label={"Resize #{card.name}"}
          ></button>
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

    layout = Dashboards.clamp_layout(card)

    %{
      id: card["id"],
      question_id: card["question_id"],
      name: card["question_name"],
      viz: card["viz"],
      result: result,
      error: error,
      col: layout["col"],
      row: layout["row"],
      size_x: layout["size_x"],
      size_y: layout["size_y"]
    }
  end

  defp layout_tuple(card) do
    {card.id, card.col, card.row, card.size_x, card.size_y}
  end

  defp restore_layout(cards, nil), do: cards

  defp restore_layout(cards, snapshot) when is_list(snapshot) do
    by_id = Map.new(snapshot, fn {id, col, row, sx, sy} -> {id, {col, row, sx, sy}} end)

    Enum.map(cards, fn card ->
      case Map.get(by_id, card.id) do
        {col, row, sx, sy} ->
          %{card | col: col, row: row, size_x: sx, size_y: sy}

        nil ->
          card
      end
    end)
  end

  defp apply_saved_layout(cards, saved) when is_list(saved) do
    by_id = Map.new(saved, &{&1["id"], Dashboards.clamp_layout(&1)})

    Enum.map(cards, fn card ->
      case Map.get(by_id, card.id) do
        %{"col" => col, "row" => row, "size_x" => sx, "size_y" => sy} ->
          %{card | col: col, row: row, size_x: sx, size_y: sy}

        _ ->
          card
      end
    end)
  end

  defp default_name(dashboards) do
    names = MapSet.new(dashboards, & &1["name"])

    if "New dashboard" in names do
      next =
        Stream.iterate(2, &(&1 + 1))
        |> Enum.find(fn n -> "New dashboard #{n}" not in names end)

      "New dashboard #{next}"
    else
      "New dashboard"
    end
  end

  defp blank_to_default(name) do
    case String.trim(to_string(name || "")) do
      "" -> "New dashboard"
      name -> name
    end
  end
end
