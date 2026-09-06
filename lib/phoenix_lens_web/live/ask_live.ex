defmodule PhoenixLensWeb.AskLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Autocomplete, Catalog, Questions, Query}

  @impl true
  def mount(params, _session, socket) do
    sql = starter_sql(params)

    {:ok,
     socket
     |> assign(:page, :ask)
     |> assign(:page_title, "New question · Lens")
     |> assign(:sql, sql)
     |> assign(:name, "")
     |> assign(:viz, "table")
     |> assign(:database_id, default_db(socket))
     |> assign(:result, nil)
     |> assign(:error, nil)
     |> assign(:editor_open, true)
     |> assign(:ac, Autocomplete.payload())}
  end

  @impl true
  def handle_event("run", params, socket) do
    sql = params["sql"] || socket.assigns.sql
    database_id = params["database_id"] || socket.assigns.database_id

    socket =
      socket
      |> assign(:sql, sql)
      |> assign(:database_id, database_id)
      |> assign(:name, params["name"] || socket.assigns.name)
      |> assign(:viz, params["viz"] || socket.assigns.viz)

    case Query.run(sql, database: database_id, actor: socket.assigns.lens_actor) do
      {:ok, result} ->
        {:noreply, socket |> assign(:result, result) |> assign(:error, nil)}

      {:error, error} ->
        {:noreply, socket |> assign(:result, nil) |> assign(:error, error)}
    end
  end

  def handle_event("change", params, socket) do
    {:noreply,
     socket
     |> assign(:sql, params["sql"] || socket.assigns.sql)
     |> assign(:name, params["name"] || socket.assigns.name)
     |> assign(:viz, params["viz"] || socket.assigns.viz)
     |> assign(:database_id, params["database_id"] || socket.assigns.database_id)}
  end

  def handle_event("toggle-editor", _params, socket) do
    {:noreply, assign(socket, :editor_open, !socket.assigns.editor_open)}
  end

  def handle_event("save", _params, socket) do
    case Questions.save(%{
           name: socket.assigns.name,
           sql: socket.assigns.sql,
           viz: socket.assigns.viz,
           database_id: socket.assigns.database_id
         }) do
      {:ok, question} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved “#{question["name"]}”")
         |> push_navigate(to: lens_path(socket, "/questions/#{question["id"]}"))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-question">
      <header class="lens-question-head">
        <input
          class="lens-title-input"
          form="ask-form"
          type="text"
          name="name"
          value={@name}
          placeholder="What is the name of your question?"
        />
        <div class="lens-question-actions">
          <button type="button" class="ghost" phx-click="toggle-editor">
            {if @editor_open, do: "Hide editor", else: "Show editor"}
          </button>
          <button type="submit" form="ask-form">Refresh</button>
          <button type="button" phx-click="save">Save</button>
        </div>
      </header>

      <form id="ask-form" phx-submit="run" phx-change="change" class="lens-ask">
        <div class="lens-filter-row">
          <label class="lens-chip">
            Database
            <select name="database_id">
              <option
                :for={db <- @lens_databases}
                value={db[:id] || db.id}
                selected={to_string(db[:id] || db.id) == to_string(@database_id)}
              >
                {db[:name] || db.name}
              </option>
            </select>
          </label>
          <label class="lens-chip">
            Visualization
            <select name="viz">
              <option value="table" selected={@viz == "table"}>Table</option>
              <option value="number" selected={@viz == "number"}>Number</option>
              <option value="bar" selected={@viz == "bar"}>Bar</option>
              <option value="line" selected={@viz == "line"}>Line</option>
              <option value="pie" selected={@viz == "pie"}>Pie</option>
              <option value="combo" selected={@viz == "combo"}>Combo</option>
            </select>
          </label>
        </div>

        <SqlEditor.editor :if={@editor_open} id="lens-sql-ask" name="sql" value={@sql} catalog={@ac} />
      </form>

      <%= if @error do %>
        <div class="lens-error">{@error.message}</div>
      <% end %>

      <section class="lens-viz-card">
        <%= if @result do %>
          <ResultTable.visualization result={@result} viz={@viz} />
        <% else %>
          <p class="lens-empty">
            Write SQL and hit Refresh. Protected fields are masked in every output.
          </p>
        <% end %>
      </section>
    </div>
    """
  end

  defp default_db(socket) do
    case socket.assigns[:lens_databases] do
      [%{id: id} | _] -> id
      [%{"id" => id} | _] -> id
      [db | _] -> db[:id] || "primary"
      _ -> "primary"
    end
  end

  defp starter_sql(%{"table" => table}) when is_binary(table) do
    source =
      Catalog.schemas()
      |> Enum.find(fn s -> s.source == table end)

    cols =
      case source do
        nil ->
          ["*"]

        schema ->
          schema.fields
          |> Enum.reject(& &1.protected)
          |> Enum.map(& &1.name)
          |> case do
            [] -> ["*"]
            names -> names
          end
      end

    ident = if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, table), do: table, else: "*"
    "SELECT #{Enum.join(cols, ", ")}\nFROM #{ident}\nLIMIT 100"
  end

  defp starter_sql(_), do: "SELECT 1"
end
