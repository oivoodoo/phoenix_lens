defmodule PhoenixLens.Settings do
  @moduledoc """
  Runtime query engine and extra DuckDB sources, stored on the host Repo.
  """

  alias PhoenixLens.{Config, DuckDB, Error}

  @engines ~w(postgresql duckdb)
  @kinds ~w(postgres mysql sqlite duckdb parquet csv json)
  @reserved ~w(
    memory repo main postgres information_schema pg_catalog temp system
    duckdb default primary catalog sys
  )
  @engine_key {__MODULE__, :engine}
  @default_retention_days 90
  @retention_choices [7, 30, 90, 180, 365, 0]

  def engines, do: @engines
  def kinds, do: @kinds
  def retention_choices, do: @retention_choices
  def default_retention_days, do: @default_retention_days

  def engine do
    engine = persisted_engine() || app_engine() || :postgresql
    :persistent_term.put(@engine_key, engine)
    engine
  rescue
    _ -> app_engine() || :persistent_term.get(@engine_key, :postgresql)
  end

  def duckdb? do
    engine() == :duckdb
  end

  def warmup do
    engine()
  end

  def put_engine(engine) do
    engine = engine |> to_string() |> String.downcase()

    cond do
      engine not in @engines ->
        {:error, %Error{message: "engine must be postgresql or duckdb", kind: :config}}

      true ->
        ensure_tables()

        repo = metadata_repo()

        if is_nil(repo) do
          {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
        else
          repo.query!(
            """
            INSERT INTO phoenix_lens_settings (id, engine, updated_at)
            VALUES (1, $1, NOW())
            ON CONFLICT (id) DO UPDATE SET engine = EXCLUDED.engine, updated_at = NOW()
            """,
            [engine],
            log: false
          )

          :persistent_term.put(@engine_key, String.to_existing_atom(engine))
          _ = DuckDB.Server.reload()
          {:ok, engine()}
        end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def audit_retention_days do
    ensure_tables()

    case query_maps("SELECT audit_retention_days FROM phoenix_lens_settings WHERE id = 1") do
      [%{"audit_retention_days" => days}] when is_integer(days) and days >= 0 ->
        days

      _ ->
        app_retention() || @default_retention_days
    end
  rescue
    _ -> app_retention() || @default_retention_days
  end

  def put_audit_retention_days(days) do
    days = parse_retention(days)

    cond do
      is_nil(days) ->
        {:error,
         %Error{
           message: "retention must be 7, 30, 90, 180, 365 days, or 0 to keep forever",
           kind: :config
         }}

      true ->
        ensure_tables()
        repo = metadata_repo()

        if is_nil(repo) do
          {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
        else
          repo.query!(
            """
            INSERT INTO phoenix_lens_settings (id, engine, audit_retention_days, updated_at)
            VALUES (1, 'postgresql', $1, NOW())
            ON CONFLICT (id) DO UPDATE
              SET audit_retention_days = EXCLUDED.audit_retention_days, updated_at = NOW()
            """,
            [days],
            log: false
          )

          _ = PhoenixLens.Audit.purge_expired()
          {:ok, days}
        end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def parse_retention(days) when is_integer(days) and days in @retention_choices, do: days

  def parse_retention(days) when is_binary(days) do
    case Integer.parse(String.trim(days)) do
      {n, ""} -> parse_retention(n)
      _ -> nil
    end
  end

  def parse_retention(_), do: nil

  def sources do
    ensure_tables()

    query_maps("""
    SELECT id, alias, kind, dsn, enabled, error, inserted_at, updated_at
    FROM phoenix_lens_sources
    ORDER BY id ASC
    """)
  rescue
    _ -> []
  end

  def add_source(attrs) when is_map(attrs) do
    with {:ok, source} <- normalize_source(attrs),
         :ok <- ensure_unique_alias(source.alias) do
      ensure_tables()
      repo = metadata_repo()

      if is_nil(repo) do
        {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
      else
        %{rows: [[id]]} =
          repo.query!(
            """
            INSERT INTO phoenix_lens_sources (alias, kind, dsn, enabled, inserted_at, updated_at)
            VALUES ($1, $2, $3, TRUE, NOW(), NOW())
            RETURNING id
            """,
            [source.alias, source.kind, source.dsn],
            log: false
          )

        _ = DuckDB.Server.reload()
        {:ok, Enum.find(sources(), &(&1["id"] == id))}
      end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def delete_source(id) do
    ensure_tables()
    repo = metadata_repo()

    if is_nil(repo) do
      {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
    else
      repo.query!(
        "DELETE FROM phoenix_lens_sources WHERE id = $1",
        [to_int(id)],
        log: false
      )

      _ = DuckDB.Server.reload()
      :ok
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def record_source_error(id, error) when is_integer(id) do
    repo = metadata_repo()

    if repo do
      repo.query!(
        "UPDATE phoenix_lens_sources SET error = $2, updated_at = NOW() WHERE id = $1",
        [id, error],
        log: false
      )
    end

    :ok
  rescue
    _ -> :ok
  end

  def clear_source_error(id) when is_integer(id) do
    record_source_error(id, nil)
  end

  def normalize_source(attrs) do
    alias_ = attrs[:alias] || attrs["alias"] || ""
    kind = attrs[:kind] || attrs["kind"] || "postgres"
    dsn = attrs[:dsn] || attrs["dsn"] || attrs[:url] || attrs["url"] || ""

    alias_ =
      alias_
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]/, "_")
      |> String.trim("_")

    kind = kind |> to_string() |> String.downcase()
    dsn = dsn |> to_string() |> String.trim()

    cond do
      alias_ == "" ->
        {:error, %Error{message: "source alias is required", kind: :config}}

      not Regex.match?(~r/\A[a-z][a-z0-9_]{0,62}\z/, alias_) ->
        {:error,
         %Error{message: "alias must be a SQL identifier (letters, digits, _)", kind: :config}}

      alias_ in @reserved ->
        {:error, %Error{message: "alias #{alias_} is reserved", kind: :config}}

      kind not in @kinds ->
        {:error,
         %Error{
           message: "kind must be one of: #{Enum.join(@kinds, ", ")}",
           kind: :config
         }}

      dsn == "" ->
        {:error, %Error{message: "connection string or path is required", kind: :config}}

      String.length(dsn) > 4000 ->
        {:error, %Error{message: "connection string is too long", kind: :config}}

      true ->
        {:ok, %{alias: alias_, kind: kind, dsn: dsn}}
    end
  end

  def redact_dsn(nil), do: ""

  def redact_dsn(dsn) when is_binary(dsn) do
    dsn
    |> String.replace(~r{(password=)('[^']*'|[^\s]+)}i, "\\1••••")
    |> String.replace(~r{(://[^:/?#]+:)([^@]+)(@)}i, "\\1••••\\3")
  end

  def redact_dsn(_), do: ""

  def ensure_tables do
    case metadata_repo() do
      nil ->
        :ok

      repo ->
        repo.query!(settings_sql(), [], log: false)
        repo.query!(settings_alter_sql(), [], log: false)
        repo.query!(sources_sql(), [], log: false)
        PhoenixLens.Protection.ensure_table()
        PhoenixLens.Tokens.ensure_table()
        PhoenixLens.Integrations.ensure_table()
        PhoenixLens.Alerts.ensure_table()
        PhoenixLens.Auth.ensure_tables()
        :ok
    end
  rescue
    _ -> :ok
  end

  def settings_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_settings (
      id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
      engine text NOT NULL DEFAULT 'postgresql',
      audit_retention_days int NOT NULL DEFAULT 90,
      updated_at timestamp(6) NOT NULL DEFAULT now()
    )
    """
  end

  def settings_alter_sql do
    """
    ALTER TABLE phoenix_lens_settings
      ADD COLUMN IF NOT EXISTS audit_retention_days int NOT NULL DEFAULT 90
    """
  end

  def sources_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_sources (
      id bigserial PRIMARY KEY,
      alias text NOT NULL UNIQUE,
      kind text NOT NULL,
      dsn text NOT NULL,
      enabled boolean NOT NULL DEFAULT true,
      error text,
      inserted_at timestamp(6) NOT NULL DEFAULT now(),
      updated_at timestamp(6) NOT NULL DEFAULT now()
    )
    """
  end

  defp persisted_engine do
    ensure_tables()

    case query_maps("SELECT engine FROM phoenix_lens_settings WHERE id = 1") do
      [%{"engine" => engine}] when engine in @engines -> String.to_existing_atom(engine)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp app_retention do
    case Application.get_env(:phoenix_lens, :audit_retention_days) do
      days when is_integer(days) and days >= 0 -> days
      days when is_binary(days) -> parse_retention(days)
      _ -> nil
    end
  end

  defp app_engine do
    case Application.get_env(:phoenix_lens, :engine) do
      engine when engine in [:postgresql, :duckdb] -> engine
      engine when engine in ["postgresql", "duckdb"] -> String.to_existing_atom(engine)
      _ -> nil
    end
  end

  defp ensure_unique_alias(alias_) do
    if Enum.any?(sources(), fn s -> s["alias"] == alias_ end) do
      {:error, %Error{message: "alias #{alias_} is already used", kind: :config}}
    else
      :ok
    end
  end

  defp query_maps(sql, params \\ []) do
    case metadata_repo() do
      nil ->
        []

      repo ->
        %{rows: rows, columns: columns} = repo.query!(sql, params, log: false)

        Enum.map(rows, fn row ->
          columns |> Enum.map(&to_string/1) |> Enum.zip(row) |> Map.new()
        end)
    end
  end

  defp metadata_repo, do: Config.get().metadata_repo

  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)
end
