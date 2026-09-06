defmodule PhoenixLensWeb.SettingsLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{DuckDB, Settings}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page, :settings)
     |> assign(:page_title, "Settings · Lens")
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

  def handle_event("reconnect", _params, socket) do
    _ = DuckDB.Server.reload()

    {:noreply,
     socket
     |> put_flash(:info, "DuckDB reconnected")
     |> refresh()}
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
         |> assign(:new_alias, "")
         |> assign(:new_kind, params["kind"] || "postgres")
         |> assign(:new_dsn, "")
         |> put_flash(:info, "Source attached")
         |> refresh()}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:new_alias, params["alias"] || "")
         |> assign(:new_kind, params["kind"] || "postgres")
         |> assign(:new_dsn, params["dsn"] || "")
         |> put_flash(:error, error.message)}
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

      <section class="lens-dash-card">
        <header class="lens-card-head">
          <h2>Query engine</h2>
        </header>

        <div class="lens-engine-grid">
          <button
            type="button"
            class={"lens-engine-card" <> if(@engine == :postgresql, do: " active", else: "")}
            phx-click="set_engine"
            phx-value-engine="postgresql"
          >
            <strong>PostgreSQL</strong>
            <span>Direct read-only queries through the host Repo (or replica URL). Default.</span>
          </button>
          <button
            type="button"
            class={"lens-engine-card" <> if(@engine == :duckdb, do: " active", else: "")}
            phx-click="set_engine"
            phx-value-engine="duckdb"
          >
            <strong>DuckDB</strong>
            <span>
              One in-process engine. Host Postgres is attached read-only as <code>repo</code>, plus any extra sources below.
            </span>
          </button>
        </div>

        <p class="lens-muted" style="margin: 16px 0 0;">
          <%= if @status.available? do %>
            duckdbex is loaded. Engine status: <strong>{status_label(@status)}</strong>.
          <% else %>
            DuckDB is optional. Add <code>{"{:duckdbex, \"~> 0.4\"}"}</code> to the host mix.exs
            and run <code>mix deps.get</code> before switching.
          <% end %>
          <%= if @status.error do %>
            <br /> <span class="lens-error-inline">{@status.error}</span>
          <% end %>
        </p>
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

        <form phx-submit="add_source" class="lens-source-form">
          <label>
            Alias
            <input
              class="lens-field"
              type="text"
              name="alias"
              value={@new_alias}
              placeholder="warehouse"
              autocomplete="off"
            />
          </label>
          <label>
            Kind
            <select class="lens-field" name="kind">
              <option :for={kind <- Settings.kinds()} value={kind} selected={kind == @new_kind}>
                {kind}
              </option>
            </select>
          </label>
          <label class="lens-source-dsn">
            Connection / path
            <input
              class="lens-field"
              type="text"
              name="dsn"
              value={@new_dsn}
              placeholder="postgresql://user:pass@host:5432/dbname"
              autocomplete="off"
            />
          </label>
          <button type="submit">Add source</button>
        </form>
        <p class="lens-muted" style="margin-top: 8px;">
          Postgres: URI or <code>host=… port=… dbname=… user=… password=…</code>.
          Files: a path or <code>https://</code> / <code>s3://</code> URL.
        </p>
      </section>
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
  end

  defp engine_flash("duckdb"), do: "Query engine is DuckDB. Host Postgres is attached as repo."
  defp engine_flash(_), do: "Query engine is PostgreSQL (direct)."

  defp status_label(%{status: :ready}), do: "ready"
  defp status_label(%{status: :idle}), do: "idle (PostgreSQL engine selected)"
  defp status_label(%{status: :unavailable}), do: "duckdbex missing"
  defp status_label(%{status: status}), do: to_string(status)

  defp source_status(%{ok?: true}), do: "attached"
  defp source_status(%{ok?: false, error: error}), do: error || "failed"
  defp source_status(_), do: "—"

  defp user_source_status(source, attached) do
    case Enum.find(attached, &(&1.alias == source["alias"])) do
      %{ok?: true} -> "attached"
      %{ok?: false, error: error} -> error || "failed"
      _ -> source["error"] || "—"
    end
  end
end
