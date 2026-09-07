defmodule PhoenixLensWeb.ProtectionLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Catalog, Config, Policy, Protection, Settings}

  @impl true
  def mount(_params, _session, socket) do
    tables = Catalog.browse()
    selected = tables |> List.first() |> then(&(&1 && &1.source))

    {:ok,
     socket
     |> assign(:page, :settings)
     |> assign(:section, :protection)
     |> assign(:page_title, "Column protection · Lens")
     |> assign(:new_global, "")
     |> assign(:new_source_col, "")
     |> assign(:source_id, default_source())
     |> assign(:table_name, selected)
     |> assign(:form_error, nil)
     |> refresh(tables)}
  end

  @impl true
  def handle_event("add_global", %{"column" => column}, socket) do
    save_rule(socket, %{scope: "global", column_name: column}, :new_global)
  end

  def handle_event("add_source", %{"column" => column}, socket) do
    save_rule(
      socket,
      %{scope: "source", source_id: socket.assigns.source_id, column_name: column},
      :new_source_col
    )
  end

  def handle_event("remove", %{"id" => id}, socket) do
    case Protection.remove(id) do
      :ok -> {:noreply, socket |> assign(:form_error, nil) |> refresh()}
      {:error, error} -> {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  def handle_event("pick_source", %{"source_id" => id}, socket) do
    {:noreply, assign(socket, :source_id, id)}
  end

  def handle_event("pick_table", %{"table" => table}, socket) do
    {:noreply, assign(socket, :table_name, table)}
  end

  def handle_event("toggle_table", %{"column" => column, "on" => on}, socket) do
    attrs = %{
      scope: "table",
      source_id: table_source(socket.assigns.table_name, socket.assigns.tables),
      table_name: socket.assigns.table_name,
      column_name: column
    }

    result =
      if on in ["true", "on", "1"] do
        Protection.add(attrs)
      else
        Protection.remove_rule("table", attrs.source_id, attrs.table_name, column)
      end

    case result do
      {:ok, _} -> {:noreply, socket |> assign(:form_error, nil) |> refresh()}
      :ok -> {:noreply, socket |> assign(:form_error, nil) |> refresh()}
      {:error, error} -> {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-settings">
      <header class="lens-browse-head">
        <div>
          <p class="lens-kicker">Admin</p>
          <h1>Column protection</h1>
          <p class="lens-muted">
            Masked cells render as <code>[redacted]</code> in the notebook, CSV, and embeds.
            Config and Ecto <code>redact: true</code> fields stay locked.
          </p>
        </div>
      </header>

      <PhoenixLensWeb.Components.SettingsNav.bar lens_prefix={@lens_prefix} section={@section} />

      <div :if={@form_error} class="lens-error">{@form_error}</div>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Global</h2>
        </header>
        <p class="lens-muted">These names are protected on every source and table.</p>
        <div class="lens-chip-row">
          <span
            :for={name <- @locked_global}
            class="lens-protect-chip is-locked"
            title="From config or Ecto redact"
          >
            {name}
          </span>
          <span :for={row <- @global_rows} class="lens-protect-chip">
            {row["column_name"]}
            <button
              type="button"
              class="ghost icon"
              phx-click="remove"
              phx-value-id={row["id"]}
              aria-label={"Remove #{row["column_name"]}"}
            >
              ×
            </button>
          </span>
        </div>
        <form phx-submit="add_global" class="lens-protect-add">
          <input
            class="lens-field"
            type="text"
            name="column"
            value={@new_global}
            placeholder="email"
            autocomplete="off"
          />
          <button type="submit">Protect</button>
        </form>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Per source</h2>
        </header>
        <p class="lens-muted">Applies to every table on that database or DuckDB attachment.</p>
        <form phx-change="pick_source" class="lens-protect-add">
          <select name="source_id" class="lens-field">
            <option :for={src <- @sources} value={src.id} selected={src.id == @source_id}>
              {src.name}
            </option>
          </select>
        </form>
        <div class="lens-chip-row">
          <span :for={row <- source_rows(@rows, @source_id)} class="lens-protect-chip">
            {row["column_name"]}
            <button
              type="button"
              class="ghost icon"
              phx-click="remove"
              phx-value-id={row["id"]}
              aria-label={"Remove #{row["column_name"]}"}
            >
              ×
            </button>
          </span>
          <span :if={source_rows(@rows, @source_id) == []} class="lens-muted">None yet for this source.</span>
        </div>
        <form phx-submit="add_source" class="lens-protect-add">
          <input
            class="lens-field"
            type="text"
            name="column"
            value={@new_source_col}
            placeholder="ip"
            autocomplete="off"
          />
          <button type="submit">Protect on source</button>
        </form>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Per table</h2>
        </header>
        <p class="lens-muted">
          Toggle columns on a table. Locked names come from global protection or Ecto.
        </p>
        <form phx-change="pick_table" class="lens-protect-add">
          <select name="table" class="lens-field">
            <option :for={t <- @tables} value={t.source} selected={t.source == @table_name}>
              {t.source}
            </option>
          </select>
        </form>
        <ul :if={@selected_table} class="lens-protect-cols">
          <li :for={field <- @selected_table.fields}>
            <label>
              <input
                type="checkbox"
                checked={field.protected}
                disabled={field.locked}
                phx-click="toggle_table"
                phx-value-column={field.name}
                phx-value-on={if field.protected, do: "false", else: "true"}
              />
              <code>{field.name}</code>
              <span class="lens-muted">{field.type}</span>
              <span :if={field.locked} class="lens-status-pill">locked</span>
            </label>
          </li>
        </ul>
        <p :if={@tables == []} class="lens-muted">No tables in the catalog yet.</p>
      </section>
    </div>
    """
  end

  defp save_rule(socket, attrs, clear_key) do
    case Protection.add(attrs) do
      {:ok, _} ->
        {:noreply, socket |> assign(clear_key, "") |> assign(:form_error, nil) |> refresh()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error.message)}
    end
  end

  defp refresh(socket, tables \\ nil) do
    tables = tables || Catalog.browse()
    config = Config.get()
    locked = locked_names(config)
    rows = Protection.list()
    selected = Enum.find(tables, &(&1.source == socket.assigns.table_name)) || List.first(tables)
    source_id = socket.assigns[:source_id] || default_source()

    selected =
      if selected do
        src = table_source(selected.source, tables)

        fields =
          Enum.map(selected.fields, fn f ->
            locked? = MapSet.member?(locked, String.downcase(f.name))
            runtime? = table_runtime?(rows, src, selected.source, f.name)
            Map.merge(f, %{locked: locked?, protected: locked? or runtime?})
          end)

        %{selected | fields: fields}
      end

    socket
    |> assign(:tables, tables)
    |> assign(:rows, rows)
    |> assign(:global_rows, Enum.filter(rows, &(&1["scope"] == "global")))
    |> assign(:locked_global, locked |> MapSet.to_list() |> Enum.sort())
    |> assign(:sources, protection_sources())
    |> assign(:source_id, source_id)
    |> assign(:selected_table, selected)
    |> assign(:table_name, selected && selected.source)
  end

  defp locked_names(config) do
    from_config =
      config.masked_fields
      |> List.wrap()
      |> Enum.map(&String.downcase(to_string(&1)))

    from_ecto =
      Policy.redact_fields(config)
      |> Enum.map(&String.downcase(to_string(&1)))

    MapSet.new(from_config ++ from_ecto)
  end

  defp protection_sources do
    dbs =
      Config.get().databases
      |> Map.values()
      |> Enum.map(fn db -> %{id: db[:id], name: db[:name] || db[:id]} end)

    extras =
      Settings.sources()
      |> Enum.map(fn s -> %{id: s["alias"], name: "#{s["alias"]} · #{s["kind"]}"} end)

    (dbs ++ extras)
    |> Enum.reject(&is_nil(&1.id))
    |> Enum.uniq_by(& &1.id)
  end

  defp default_source do
    case protection_sources() do
      [%{id: id} | _] -> id
      _ -> "primary"
    end
  end

  defp source_rows(rows, source_id) do
    Enum.filter(rows, fn row ->
      row["scope"] == "source" and row["source_id"] == source_id
    end)
  end

  defp table_source(table_name, tables) do
    case Enum.find(tables, &(&1.source == table_name)) do
      %{module: db} when is_binary(db) and db not in ["postgres", ""] -> db
      _ -> "primary"
    end
  end

  defp table_runtime?(rows, source_id, table, column) do
    col = String.downcase(column)
    table = String.downcase(to_string(table))

    Enum.any?(rows, fn row ->
      row["scope"] == "table" and String.downcase(to_string(row["table_name"])) == table and
        String.downcase(to_string(row["column_name"])) == col and
        row["source_id"] in [source_id, "primary", ""]
    end)
  end
end
