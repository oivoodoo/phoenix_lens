defmodule PhoenixLensWeb.AskLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Autocomplete, Catalog, Notebook, Questions, Query}

  @ops [
    {"=", "equals"},
    {"!=", "not equals"},
    {">", "greater than"},
    {"<", "less than"},
    {">=", "at least"},
    {"<=", "at most"},
    {"contains", "contains"},
    {"is_null", "is empty"},
    {"not_null", "is not empty"}
  ]

  @aggs [
    {"count", "Count of rows"},
    {"sum", "Sum of …"},
    {"avg", "Average of …"},
    {"min", "Min of …"},
    {"max", "Max of …"}
  ]

  @impl true
  def mount(params, _session, socket) do
    ac = Autocomplete.payload()
    tables = Enum.map(ac.tables, & &1.name)
    table = params["table"]
    mode = if params["mode"] == "sql", do: :sql, else: :notebook

    nb =
      if is_binary(table) and table in tables do
        Notebook.pick_table(%Notebook{}, table)
      else
        %Notebook{}
      end

    sql =
      case Notebook.to_sql(nb) do
        {:ok, generated} -> generated
        _ -> starter_sql(params)
      end

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
     |> assign(:show_sql, false)
     |> assign(:mode, mode)
     |> assign(:notebook, nb)
     |> assign(:tables, tables)
     |> assign(:columns, columns_for(ac, nb.table))
     |> assign(:ops, @ops)
     |> assign(:aggs, @aggs)
     |> assign(:ac, ac)}
  end

  @impl true
  def handle_event("run", params, socket) do
    sql = params["sql"] || socket.assigns.sql
    run_sql(socket, sql, params)
  end

  def handle_event("visualize", _params, socket) do
    case Notebook.to_sql(socket.assigns.notebook) do
      {:ok, sql} ->
        run_sql(assign(socket, :sql, sql), sql, %{})

      {:error, error} ->
        {:noreply, assign(socket, :error, error)}
    end
  end

  def handle_event("change", params, socket) do
    {:noreply,
     socket
     |> assign(:sql, params["sql"] || socket.assigns.sql)
     |> assign(:name, params["name"] || socket.assigns.name)
     |> assign(:database_id, params["database_id"] || socket.assigns.database_id)}
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode = if mode == "sql", do: :sql, else: :notebook

    socket =
      if mode == :sql do
        case Notebook.to_sql(socket.assigns.notebook) do
          {:ok, sql} -> assign(socket, :sql, sql)
          _ -> socket
        end
      else
        socket
      end

    {:noreply, assign(socket, :mode, mode)}
  end

  def handle_event("toggle-editor", _params, socket) do
    {:noreply, assign(socket, :editor_open, !socket.assigns.editor_open)}
  end

  def handle_event("toggle_sql", _params, socket) do
    {:noreply, assign(socket, :show_sql, !socket.assigns.show_sql)}
  end

  def handle_event("pick_table", %{"table" => table}, socket) do
    {nb, cols} =
      if table in ["", nil] do
        {%Notebook{}, []}
      else
        {Notebook.pick_table(socket.assigns.notebook, table),
         columns_for(socket.assigns.ac, table)}
      end

    {:noreply, socket |> assign(:notebook, nb) |> assign(:columns, cols) |> sync_sql(nb)}
  end

  def handle_event("add_filter", _params, socket) do
    nb =
      update_in(
        socket.assigns.notebook.filters,
        &(&1 ++ [new_filter(&1, socket.assigns.columns)])
      )

    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("remove_filter", %{"id" => id}, socket) do
    id = String.to_integer(id)
    nb = update_in(socket.assigns.notebook.filters, &Enum.reject(&1, fn f -> f.id == id end))
    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("update_filter", params, socket) do
    id = (params["filter_id"] || params["id"]) |> to_string() |> String.to_integer()

    nb =
      update_in(socket.assigns.notebook.filters, fn filters ->
        Enum.map(filters, fn f ->
          if f.id == id,
            do: %{
              f
              | column: params["column"] || f.column,
                op: params["op"] || f.op,
                value: params["value"] || f.value
            },
            else: f
        end)
      end)

    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("add_agg", _params, socket) do
    nb =
      update_in(socket.assigns.notebook.aggregations, fn aggs ->
        aggs ++ [%{id: next_id(aggs), fun: "count", column: nil}]
      end)

    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("remove_agg", %{"id" => id}, socket) do
    id = String.to_integer(id)
    nb = update_in(socket.assigns.notebook.aggregations, &Enum.reject(&1, fn a -> a.id == id end))
    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("update_agg", params, socket) do
    id = (params["agg_id"] || params["id"]) |> to_string() |> String.to_integer()

    nb =
      update_in(socket.assigns.notebook.aggregations, fn aggs ->
        Enum.map(aggs, fn a ->
          if a.id == id do
            fun = params["fun"] || a.fun
            col = if fun == "count", do: nil, else: params["column"] || a.column
            %{a | fun: fun, column: col}
          else
            a
          end
        end)
      end)

    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("add_breakout", _params, socket) do
    col = socket.assigns.columns |> List.first() |> then(&(&1 && &1.name))
    nb = update_in(socket.assigns.notebook.breakouts, &(&1 ++ List.wrap(col)))
    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("remove_breakout", %{"index" => index}, socket) do
    i = String.to_integer(index)
    nb = update_in(socket.assigns.notebook.breakouts, &List.delete_at(&1, i))
    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("update_breakout", %{"index" => index, "column" => col}, socket) do
    i = String.to_integer(index)
    nb = update_in(socket.assigns.notebook.breakouts, &List.replace_at(&1, i, col))
    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
  end

  def handle_event("set_limit", %{"limit" => limit}, socket) do
    n =
      case Integer.parse(to_string(limit)) do
        {int, _} -> int
        :error -> 100
      end

    nb = %{socket.assigns.notebook | limit: n}
    {:noreply, assign(socket, :notebook, nb) |> sync_sql(nb)}
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
  def handle_info({:preview_viz, viz}, socket) do
    {:noreply, assign(socket, :viz, viz)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-question">
      <header class="lens-question-head">
        <form phx-change="change" class="lens-title-form">
          <input
            class="lens-title-input"
            type="text"
            name="name"
            value={@name}
            placeholder="What is the name of your question?"
            phx-debounce="blur"
          />
        </form>
        <div class="lens-question-actions">
          <div class="lens-mode">
            <button
              type="button"
              class={if @mode == :notebook, do: "active"}
              phx-click="set_mode"
              phx-value-mode="notebook"
            >
              Notebook
            </button>
            <button
              type="button"
              class={if @mode == :sql, do: "active"}
              phx-click="set_mode"
              phx-value-mode="sql"
            >
              Native query
            </button>
          </div>
          <button type="button" phx-click="save">Save</button>
        </div>
      </header>

      <%= if @mode == :notebook do %>
        <.notebook
          notebook={@notebook}
          tables={@tables}
          columns={@columns}
          ops={@ops}
          aggs={@aggs}
          sql={@sql}
          show_sql={@show_sql}
        />
      <% else %>
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
            <button type="submit">Refresh</button>
          </div>
          <SqlEditor.editor
            :if={@editor_open}
            id="lens-sql-ask"
            name="sql"
            value={@sql}
            catalog={@ac}
          />
        </form>
      <% end %>

      <%= if @error do %>
        <div class="lens-error">{@error.message}</div>
      <% end %>

      <section class="lens-viz-card">
        <%= if @result do %>
          <.live_component
            module={PhoenixLensWeb.ResultPreview}
            id="ask-preview"
            result={@result}
            viz={@viz}
          />
        <% else %>
          <p class="lens-empty">
            Pick a table, filter or summarize, then Visualize. Protected fields stay masked.
          </p>
        <% end %>
      </section>
    </div>
    """
  end

  attr :notebook, :map, required: true
  attr :tables, :list, required: true
  attr :columns, :list, required: true
  attr :ops, :list, required: true
  attr :aggs, :list, required: true
  attr :sql, :string, required: true
  attr :show_sql, :boolean, required: true

  def notebook(assigns) do
    ~H"""
    <div class="lens-notebook">
      <section class="lens-nb-step">
        <div class="lens-nb-head">
          <span class="lens-nb-num">1</span>
          <h2>Pick your data</h2>
        </div>
        <form phx-change="pick_table">
          <select name="table" class="lens-field">
            <option value="">Select a table…</option>
            <option :for={t <- @tables} value={t} selected={t == @notebook.table}>{t}</option>
          </select>
        </form>
      </section>

      <section class="lens-nb-step">
        <div class="lens-nb-head">
          <span class="lens-nb-num">2</span>
          <h2>Filter</h2>
          <button
            type="button"
            class="ghost tiny"
            phx-click="add_filter"
            disabled={is_nil(@notebook.table)}
          >
            + Add a filter
          </button>
        </div>
        <form
          :for={f <- @notebook.filters}
          class="lens-nb-row"
          phx-change="update_filter"
          phx-value-id={f.id}
        >
          <input type="hidden" name="filter_id" value={f.id} />
          <select name="column" class="lens-field">
            <option :for={col <- @columns} value={col.name} selected={col.name == f.column}>
              {col.name}{if col.protected, do: " (redacted)"}
            </option>
          </select>
          <select name="op" class="lens-field">
            <option :for={{op, label} <- @ops} value={op} selected={op == f.op}>{label}</option>
          </select>
          <input
            :if={f.op not in ["is_null", "not_null"]}
            class="lens-field"
            type="text"
            name="value"
            value={f.value}
            placeholder="value"
          />
          <button type="button" class="ghost tiny" phx-click="remove_filter" phx-value-id={f.id}>✕</button>
        </form>
        <p :if={@notebook.filters == []} class="lens-muted">No filters — all rows from this table.</p>
      </section>

      <section class="lens-nb-step">
        <div class="lens-nb-head">
          <span class="lens-nb-num">3</span>
          <h2>Summarize</h2>
          <button
            type="button"
            class="ghost tiny"
            phx-click="add_agg"
            disabled={is_nil(@notebook.table)}
          >
            + Add a metric
          </button>
        </div>
        <form
          :for={a <- @notebook.aggregations}
          class="lens-nb-row"
          phx-change="update_agg"
          phx-value-id={a.id}
        >
          <input type="hidden" name="agg_id" value={a.id} />
          <select name="fun" class="lens-field">
            <option :for={{fun, label} <- @aggs} value={fun} selected={fun == a.fun}>{label}</option>
          </select>
          <select :if={a.fun != "count"} name="column" class="lens-field">
            <option :for={col <- @columns} value={col.name} selected={col.name == a.column}>
              {col.name}
            </option>
          </select>
          <button type="button" class="ghost tiny" phx-click="remove_agg" phx-value-id={a.id}>✕</button>
        </form>

        <div class="lens-nb-breakouts">
          <span class="lens-muted">by</span>
          <form
            :for={{col, i} <- Enum.with_index(@notebook.breakouts)}
            class="lens-nb-row"
            phx-change="update_breakout"
          >
            <input type="hidden" name="index" value={i} />
            <select name="column" class="lens-field">
              <option :for={c <- @columns} value={c.name} selected={c.name == col}>{c.name}</option>
            </select>
            <button type="button" class="ghost tiny" phx-click="remove_breakout" phx-value-index={i}>✕</button>
          </form>
          <button
            type="button"
            class="ghost tiny"
            phx-click="add_breakout"
            disabled={is_nil(@notebook.table)}
          >
            + Group by
          </button>
        </div>
      </section>

      <section class="lens-nb-step">
        <div class="lens-nb-head">
          <span class="lens-nb-num">4</span>
          <h2>Row limit</h2>
        </div>
        <form phx-change="set_limit">
          <input
            class="lens-field"
            type="number"
            min="1"
            max="10000"
            name="limit"
            value={@notebook.limit}
          />
        </form>
      </section>

      <div class="lens-nb-run">
        <button type="button" phx-click="visualize" disabled={is_nil(@notebook.table)}>Visualize</button>
        <button type="button" class="ghost" phx-click="toggle_sql">View SQL</button>
      </div>

      <pre :if={@show_sql} class="lens-nb-sql">{@sql}</pre>
    </div>
    """
  end

  defp run_sql(socket, sql, params) do
    database_id = params["database_id"] || socket.assigns.database_id

    socket =
      socket
      |> assign(:sql, sql)
      |> assign(:database_id, database_id)
      |> assign(:name, params["name"] || socket.assigns.name)

    case Query.run(sql, database: database_id, actor: socket.assigns.lens_actor) do
      {:ok, result} ->
        {:noreply, socket |> assign(:result, result) |> assign(:error, nil)}

      {:error, error} ->
        {:noreply, socket |> assign(:result, nil) |> assign(:error, error)}
    end
  end

  defp sync_sql(socket, nb) do
    case Notebook.to_sql(nb) do
      {:ok, sql} -> assign(socket, :sql, sql)
      _ -> socket
    end
  end

  defp columns_for(_ac, nil), do: []

  defp columns_for(ac, table) do
    case Enum.find(ac.tables, &(&1.name == table)) do
      nil -> []
      t -> t.columns
    end
  end

  defp new_filter(filters, columns) do
    col = columns |> List.first() |> then(&(&1 && &1.name))
    %{id: next_id(filters), column: col || "", op: "=", value: ""}
  end

  defp next_id(items) do
    items
    |> Enum.map(fn
      %{id: id} -> id
      _ -> 0
    end)
    |> Enum.max(fn -> 0 end)
    |> then(&(&1 + 1))
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
    source = Catalog.schemas() |> Enum.find(fn s -> s.source == table end)

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

    ident = if Regex.match?(~r/\A[a-zA-Z_][A-Za-z0-9_]*\z/, table), do: table, else: "*"
    "SELECT #{Enum.join(cols, ", ")}\nFROM #{ident}\nLIMIT 100"
  end

  defp starter_sql(_), do: "SELECT 1"
end
