defmodule PhoenixLensWeb.SettingsLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{DuckDB, Settings}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :settings)
     |> assign(:section, :engine)
     |> assign(:page_title, "Settings · Lens")
     |> assign(:source_modal, false)
     |> assign(:source_error, nil)
     |> assign(:new_alias, "")
     |> assign(:new_kind, "postgres")
     |> assign(:new_dsn, "")
     |> refresh()}
  end

  @impl true
  def handle_event("set_engine", %{"engine" => engine}, socket) do
    case Settings.put_engine(engine) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, engine_flash(engine))
         |> refresh()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  def handle_event("set_retention", %{"days" => days}, socket) do
    parsed = Settings.parse_retention(days)

    cond do
      parsed == socket.assigns.retention_days ->
        {:noreply, socket}

      true ->
        case Settings.put_audit_retention_days(days) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Audit retention updated")
             |> refresh()}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, error.message)}
        end
    end
  end

  def handle_event("reconnect", _params, socket) do
    _ = DuckDB.Server.reload()

    {:noreply,
     socket
     |> put_flash(:info, "DuckDB reconnected")
     |> refresh()}
  end

  def handle_event("open_source_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:source_modal, true)
     |> assign(:source_error, nil)
     |> assign(:new_alias, "")
     |> assign(:new_kind, "postgres")
     |> assign(:new_dsn, "")}
  end

  def handle_event("close_source_modal", _params, socket) do
    {:noreply, socket |> assign(:source_modal, false) |> assign(:source_error, nil)}
  end

  def handle_event("source_form", params, socket) do
    {:noreply,
     socket
     |> assign(:new_alias, params["alias"] || socket.assigns.new_alias)
     |> assign(:new_kind, params["kind"] || socket.assigns.new_kind)
     |> assign(:new_dsn, params["dsn"] || socket.assigns.new_dsn)}
  end

  def handle_event("add_source", params, socket) do
    attrs = %{
      alias: params["alias"],
      kind: params["kind"],
      dsn: params["dsn"]
    }

    case Settings.add_source(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:source_modal, false)
         |> assign(:source_error, nil)
         |> assign(:new_alias, "")
         |> assign(:new_kind, "postgres")
         |> assign(:new_dsn, "")
         |> put_flash(:info, "Source attached")
         |> refresh()}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:new_alias, params["alias"] || "")
         |> assign(:new_kind, params["kind"] || "postgres")
         |> assign(:new_dsn, params["dsn"] || "")
         |> assign(:source_error, error.message)}
    end
  end

  def handle_event("remove_source", %{"id" => id}, socket) do
    case Settings.delete_source(id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Source removed")
         |> refresh()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-settings">
      <header class="lens-browse-head">
        <div>
          <p class="lens-kicker">Admin</p>
          <h1>Settings</h1>
          <p class="lens-muted">
            Query through PostgreSQL directly, or switch to one DuckDB engine that attaches
            the host Repo and extra databases or files.
          </p>
        </div>
      </header>

      <PhoenixLensWeb.Components.SettingsNav.bar lens_prefix={@lens_prefix} section={@section} />

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Query engine</h2>
        </header>

        <div class="lens-engine-grid" role="radiogroup" aria-label="Query engine">
          <button
            type="button"
            role="radio"
            aria-checked={@engine == :postgresql}
            class={engine_card_class(@engine, :postgresql)}
            phx-click="set_engine"
            phx-value-engine="postgresql"
          >
            <span class="lens-engine-check" aria-hidden="true"></span>
            <span class="lens-engine-copy">
              <span class="lens-engine-name">PostgreSQL</span>
              <span class="lens-engine-desc">
                Direct read-only queries through the host Repo or replica URL.
              </span>
            </span>
          </button>
          <button
            type="button"
            role="radio"
            aria-checked={@engine == :duckdb}
            class={engine_card_class(@engine, :duckdb)}
            phx-click="set_engine"
            phx-value-engine="duckdb"
          >
            <span class="lens-engine-check" aria-hidden="true"></span>
            <span class="lens-engine-copy">
              <span class="lens-engine-name">DuckDB</span>
              <span class="lens-engine-desc">
                One engine. Host Postgres attaches as <code>repo</code>, plus extra sources below.
              </span>
            </span>
          </button>
        </div>

        <p class="lens-engine-status">
          <%= if @status.available? do %>
            <span class={"lens-status-pill is-#{@status.status}"}>{status_label(@status)}</span>
            duckdbex loaded
          <% else %>
            DuckDB needs <code>{"{:duckdbex, \"~> 0.4\"}"}</code>
            in the host mix.exs, then <code>mix deps.get</code>.
          <% end %>
        </p>
        <p :if={@status.error} class="lens-error-inline">{@status.error}</p>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Audit log</h2>
        </header>
        <p class="lens-muted">
          Query history is stored without result cells. Rows older than this window are deleted.
        </p>
        <form phx-change="set_retention" class="lens-retention">
          <label>
            Keep logs for
            <select name="days" class="lens-field">
              <option
                :for={days <- Settings.retention_choices()}
                value={days}
                selected={days == @retention_days}
              >
                {retention_label(days)}
              </option>
            </select>
          </label>
        </form>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Host database</h2>
          <%= if @engine == :duckdb do %>
            <button type="button" class="ghost" phx-click="reconnect">Reconnect</button>
          <% end %>
        </header>
        <p class="lens-muted">
          Always attached when DuckDB is on, as <code>repo</code>, using the configured Ecto Repo
          (read-only). Query <code>users</code>
          or <code>repo.users</code>. Extra config <code>databases:</code>
          attach under their ids.
        </p>
        <table class="lens-table" style="margin-top: 12px;">
          <thead>
            <tr>
              <th>Alias</th>
              <th>Kind</th>
              <th>Connection</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={source <- @host_sources}>
              <td><code>{source.alias}</code></td>
              <td>{source.kind}</td>
              <td><code>{source.dsn}</code></td>
              <td>{source_status(source)}</td>
            </tr>
            <tr :if={@host_sources == []}>
              <td colspan="4" class="lens-muted">Host Repo is not attached yet.</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Extra sources</h2>
          <button type="button" phx-click="open_source_modal">Add source</button>
        </header>
        <p class="lens-muted">
          Attach more Postgres databases, SQLite, DuckDB files, Parquet, CSV, or JSON to the
          same DuckDB engine. Query them as <code>alias.table</code> (or the alias itself for files).
        </p>

        <table class="lens-table" style="margin-top: 12px;">
          <thead>
            <tr>
              <th>Alias</th>
              <th>Kind</th>
              <th>Connection / path</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@user_sources == []}>
              <td colspan="5" class="lens-muted">No extra sources yet.</td>
            </tr>
            <tr :for={source <- @user_sources}>
              <td><code>{source["alias"]}</code></td>
              <td>{source["kind"]}</td>
              <td><code>{Settings.redact_dsn(source["dsn"])}</code></td>
              <td>{user_source_status(source, @attached)}</td>
              <td>
                <button
                  type="button"
                  class="ghost tiny"
                  phx-click="remove_source"
                  phx-value-id={source["id"]}
                  data-confirm="Detach this source?"
                >
                  Remove
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <div
        :if={@source_modal}
        class="lens-modal-backdrop"
        phx-window-keydown="close_source_modal"
        phx-key="escape"
      >
        <div
          class="lens-modal"
          role="dialog"
          aria-modal="true"
          aria-labelledby="lens-source-modal-title"
          phx-click-away="close_source_modal"
        >
          <header class="lens-modal-head">
            <h2 id="lens-source-modal-title">Add source</h2>
            <button
              type="button"
              class="ghost icon"
              phx-click="close_source_modal"
              aria-label="Close"
            >
              ×
            </button>
          </header>
          <form phx-submit="add_source" phx-change="source_form" class="lens-modal-form">
            <div :if={@source_error} class="lens-error">{@source_error}</div>
            <label>
              Alias
              <input
                class="lens-field"
                type="text"
                name="alias"
                value={@new_alias}
                placeholder="warehouse"
                autocomplete="off"
                autofocus
              />
            </label>
            <label>
              Kind
              <select class="lens-field" name="kind">
                <option :for={kind <- Settings.kinds()} value={kind} selected={kind == @new_kind}>
                  {kind_label(kind)}
                </option>
              </select>
            </label>
            <label>
              {dsn_label(@new_kind)}
              <input
                class="lens-field"
                type="text"
                name="dsn"
                value={@new_dsn}
                placeholder={dsn_placeholder(@new_kind)}
                autocomplete="off"
              />
            </label>
            <p class="lens-muted">{dsn_hint(@new_kind)}</p>
            <div class="lens-modal-actions">
              <button type="button" class="ghost" phx-click="close_source_modal">Cancel</button>
              <button type="submit">Add source</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp refresh(socket) do
    status = DuckDB.Server.status()
    sources = Settings.sources()

    socket
    |> assign(:engine, Settings.engine())
    |> assign(:status, status)
    |> assign(:attached, status.attached)
    |> assign(:host_sources, Enum.filter(status.attached, & &1.builtin?))
    |> assign(:user_sources, sources)
    |> assign(:retention_days, Settings.audit_retention_days())
  end

  defp retention_label(0), do: "Forever"
  defp retention_label(days), do: "#{days} days"

  defp engine_card_class(current, engine) do
    if current == engine, do: "lens-engine-card is-active", else: "lens-engine-card"
  end

  defp engine_flash("duckdb"), do: "Query engine is DuckDB. Host Postgres is attached as repo."
  defp engine_flash(_), do: "Query engine is PostgreSQL (direct)."

  defp status_label(%{status: :ready}), do: "ready"
  defp status_label(%{status: :idle}), do: "idle"
  defp status_label(%{status: :unavailable}), do: "unavailable"
  defp status_label(%{status: status}), do: to_string(status)

  defp source_status(%{ok?: true}), do: "attached"
  defp source_status(%{ok?: false, error: error}), do: error || "failed"
  defp source_status(_), do: "—"

  defp kind_label("postgres"), do: "PostgreSQL"
  defp kind_label("mysql"), do: "MySQL"
  defp kind_label("sqlite"), do: "SQLite"
  defp kind_label("duckdb"), do: "DuckDB file"
  defp kind_label("parquet"), do: "Parquet"
  defp kind_label("csv"), do: "CSV"
  defp kind_label("json"), do: "JSON"
  defp kind_label(kind), do: kind

  defp dsn_label(kind) when kind in ["parquet", "csv", "json"], do: "File path or URL"
  defp dsn_label(kind) when kind in ["postgres", "mysql"], do: "Connection"
  defp dsn_label(_), do: "File path"

  defp dsn_placeholder("postgres"), do: "postgresql://user:pass@host:5432/dbname"
  defp dsn_placeholder("mysql"), do: "mysql://user:pass@host:3306/dbname"
  defp dsn_placeholder("sqlite"), do: "/path/to/file.sqlite"
  defp dsn_placeholder("duckdb"), do: "/path/to/file.duckdb"
  defp dsn_placeholder("parquet"), do: "/path/to/file.parquet"
  defp dsn_placeholder("csv"), do: "/path/to/file.csv"
  defp dsn_placeholder("json"), do: "/path/to/file.json"
  defp dsn_placeholder(_), do: "/path/to/file"

  defp dsn_hint("postgres"), do: "URI or host=… port=… dbname=… user=… password=…"

  defp dsn_hint("mysql"),
    do: "mysql://user:pass@host:3306/dbname or host=… user=… password=… port=3306 database=…"

  defp dsn_hint(kind) when kind in ["parquet", "csv", "json"],
    do: "Local path or https:// / s3:// URL."

  defp dsn_hint(_), do: "Absolute path to the file on this machine."

  defp user_source_status(source, attached) do
    case Enum.find(attached, &(&1.alias == source["alias"])) do
      %{ok?: true} -> "attached"
      %{ok?: false, error: error} -> error || "failed"
      _ -> source["error"] || "—"
    end
  end
end
