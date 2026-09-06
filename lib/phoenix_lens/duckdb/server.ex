defmodule PhoenixLens.DuckDB.Server do
  @moduledoc false
  use GenServer

  alias PhoenixLens.{DuckDB, Error, Settings}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def reload(server \\ __MODULE__) do
    if Process.whereis(server) do
      GenServer.call(server, :reload, 30_000)
    else
      {:error, %Error{message: "DuckDB engine is not running", kind: :config}}
    end
  end

  def query(sql, opts \\ []) when is_binary(sql) do
    server = Keyword.get(opts, :server, __MODULE__)
    timeout = Keyword.get(opts, :timeout, 15_000)

    if Process.whereis(server) do
      GenServer.call(server, {:query, sql}, timeout)
    else
      {:error, %Error{message: "DuckDB engine is not running", kind: :config}}
    end
  end

  def tables(server \\ __MODULE__) do
    if Process.whereis(server) do
      GenServer.call(server, :tables, 15_000)
    else
      []
    end
  end

  def status(server \\ __MODULE__) do
    if Process.whereis(server) do
      GenServer.call(server, :status)
    else
      %{
        status: :stopped,
        error: "DuckDB engine is not running",
        attached: [],
        available?: DuckDB.available?()
      }
    end
  end

  @impl true
  def init(_opts) do
    send(self(), :boot)
    {:ok, empty_state()}
  end

  @impl true
  def handle_info(:boot, state) do
    {:noreply, boot(close(state))}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    state = boot(close(state))
    {:reply, {:ok, public_status(state)}, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, public_status(state), state}
  end

  def handle_call(:tables, _from, state) do
    tables =
      if state.conn do
        DuckDB.tables(state.conn)
      else
        []
      end

    {:reply, tables, state}
  end

  def handle_call({:query, sql}, from, %{status: :idle} = state) do
    if Settings.engine() == :duckdb do
      handle_call({:query, sql}, from, boot(close(state)))
    else
      message = "DuckDB engine is not selected. Open Settings to switch."
      {:reply, {:error, %Error{message: message, kind: :config}}, state}
    end
  end

  def handle_call({:query, sql}, _from, %{status: :ready, conn: conn} = state) do
    {:reply, DuckDB.query(conn, sql), state}
  end

  def handle_call({:query, _sql}, _from, %{status: :unavailable} = state) do
    {:reply, {:error, %Error{message: DuckDB.missing_message(), kind: :config}}, state}
  end

  def handle_call({:query, _sql}, _from, state) do
    message = state.error || "DuckDB engine is not connected. Open Settings and switch to DuckDB."
    {:reply, {:error, %Error{message: message, kind: :config}}, state}
  end

  @impl true
  def terminate(_reason, state) do
    close(state)
    :ok
  end

  defp boot(state) do
    Settings.warmup()

    cond do
      not DuckDB.available?() ->
        %{state | status: :unavailable, error: DuckDB.missing_message()}

      Settings.engine() != :duckdb ->
        %{state | status: :idle, error: nil}

      true ->
        connect(state)
    end
  end

  defp connect(state) do
    case DuckDB.open_memory() do
      {:ok, %{db: db, conn: conn}} ->
        sources = DuckDB.configured_sources()
        attached = DuckDB.attach_all(conn, sources)
        reserved = Enum.map(attached, & &1.alias)
        _ = DuckDB.alias_host_tables(conn, DuckDB.host_alias(), reserved)

        errors =
          attached
          |> Enum.reject(& &1.ok?)
          |> Enum.map(fn s -> "#{s.alias}: #{s.error}" end)

        error =
          case errors do
            [] -> nil
            list -> Enum.join(list, "; ")
          end

        %{
          state
          | db: db,
            conn: conn,
            status: :ready,
            error: error,
            attached: attached
        }

      {:error, %Error{} = error} ->
        %{state | status: :error, error: error.message}
    end
  end

  defp close(%{db: db, conn: conn} = state) do
    if conn && DuckDB.available?(), do: Duckdbex.release(conn)
    if db && DuckDB.available?(), do: Duckdbex.release(db)
    %{state | db: nil, conn: nil, attached: []}
  rescue
    _ -> %{state | db: nil, conn: nil, attached: []}
  end

  defp empty_state do
    %{
      db: nil,
      conn: nil,
      status: :idle,
      error: nil,
      attached: []
    }
  end

  defp public_status(state) do
    %{
      status: state.status,
      error: state.error,
      available?: DuckDB.available?(),
      engine: Settings.engine(),
      attached:
        Enum.map(state.attached, fn source ->
          %{
            alias: source.alias,
            kind: source.kind,
            builtin?: source.builtin?,
            ok?: source.ok?,
            error: source.error,
            dsn: Settings.redact_dsn(source.dsn)
          }
        end)
    }
  end
end
