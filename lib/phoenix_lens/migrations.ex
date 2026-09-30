defmodule PhoenixLens.Migrations do
  @moduledoc """
  Ecto migrations for questions, dashboards, and the audit log.

      defmodule MyApp.Repo.Migrations.AddPhoenixLens do
        use Ecto.Migration

        def up, do: PhoenixLens.Migrations.up()
        def down, do: PhoenixLens.Migrations.down()
      end

  Upgrading an existing 0.1.x database: add another migration and call `up/0`
  again. It is idempotent. Missing columns are added only when
  `information_schema` says they are absent, so a database that already has
  them does not take `ACCESS EXCLUSIVE`.

      defmodule MyApp.Repo.Migrations.UpgradePhoenixLens do
        use Ecto.Migration

        def up, do: PhoenixLens.Migrations.up()
        def down, do: :ok
      end
  """

  @ready {__MODULE__, :ready}
  @backoff {__MODULE__, :backoff}
  @backoff_ms 60_000
  @ddl_timeout 10_000

  def statements do
    [
      """
      CREATE TABLE IF NOT EXISTS phoenix_lens_questions (
        id bigserial PRIMARY KEY,
        name text NOT NULL,
        sql text NOT NULL,
        viz text NOT NULL DEFAULT 'table',
        database_id text NOT NULL DEFAULT 'primary',
        inserted_at timestamp(6) NOT NULL DEFAULT now(),
        updated_at timestamp(6) NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS phoenix_lens_dashboards (
        id bigserial PRIMARY KEY,
        name text NOT NULL,
        inserted_at timestamp(6) NOT NULL DEFAULT now(),
        updated_at timestamp(6) NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS phoenix_lens_dashboard_cards (
        id bigserial PRIMARY KEY,
        dashboard_id bigint NOT NULL REFERENCES phoenix_lens_dashboards(id) ON DELETE CASCADE,
        question_id bigint NOT NULL REFERENCES phoenix_lens_questions(id) ON DELETE CASCADE,
        position int NOT NULL,
        date_column text,
        col int NOT NULL DEFAULT 0,
        row int NOT NULL DEFAULT 0,
        size_x int NOT NULL DEFAULT 6,
        size_y int NOT NULL DEFAULT 5,
        inserted_at timestamp(6) NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS phoenix_lens_audit (
        id bigserial PRIMARY KEY,
        actor text NOT NULL,
        database_id text NOT NULL,
        question_id bigint,
        sql_redacted text NOT NULL,
        query_hash text NOT NULL,
        row_count int,
        duration_ms int,
        masked_columns text[],
        truncated boolean NOT NULL DEFAULT false,
        error text,
        inserted_at timestamp(6) NOT NULL DEFAULT now()
      )
      """,
      "CREATE INDEX IF NOT EXISTS phoenix_lens_audit_inserted_at_idx ON phoenix_lens_audit (inserted_at DESC)",
      "CREATE INDEX IF NOT EXISTS phoenix_lens_audit_query_hash_idx ON phoenix_lens_audit (query_hash)",
      PhoenixLens.Dashboards.layout_alter_sql(),
      PhoenixLens.Settings.settings_sql(),
      PhoenixLens.Settings.settings_alter_sql(),
      PhoenixLens.Settings.sources_sql(),
      PhoenixLens.Protection.table_sql(),
      PhoenixLens.Tokens.table_sql(),
      PhoenixLens.Integrations.table_sql(),
      PhoenixLens.Alerts.table_sql(),
      PhoenixLens.Auth.auth_sql(),
      PhoenixLens.Auth.passkeys_sql(),
      PhoenixLens.Operator.table_sql()
    ]
  end

  @doc """
  Creates any missing Lens tables and columns.

  Successful runs are remembered for this node. Request paths should call
  `ensure_once/1`, which backs off after a failure instead of repeating DDL.
  """
  def ensure_all(repo) when not is_nil(repo) do
    if ready?(repo) do
      :ok
    else
      Enum.each(statements(), fn sql ->
        repo.query!(sql, [], timeout: @ddl_timeout, log: false)
      end)

      :persistent_term.put(ready_key(repo), true)
      :ok
    end
  end

  @doc """
  Runs `ensure_all/1` at most once per node. A failed attempt waits #{@backoff_ms}ms
  before trying again, so a dashboard request cannot queue DDL on every card.
  """
  def ensure_once(nil), do: :ok

  def ensure_once(repo) do
    cond do
      ready?(repo) ->
        :ok

      backing_off?(repo) ->
        :ok

      true ->
        try do
          ensure_all(repo)
        rescue
          _ ->
            :persistent_term.put(backoff_key(repo), System.monotonic_time(:millisecond))
            :ok
        end
    end
  end

  @doc false
  def add_columns_unless_exists(table, columns)
      when is_binary(table) and is_list(columns) do
    alters =
      Enum.map_join(columns, "\n", fn {column, definition} ->
        """
          IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = current_schema()
              AND table_name = '#{table}'
              AND column_name = '#{column}'
          ) THEN
            ALTER TABLE #{table} ADD COLUMN #{column} #{definition};
          END IF;
        """
      end)

    """
    DO $$
    BEGIN
    #{alters}
    END $$
    """
  end

  defp ready?(repo), do: :persistent_term.get(ready_key(repo), false) == true

  defp ready_key(repo), do: {@ready, repo}

  defp backoff_key(repo), do: {@backoff, repo}

  defp backing_off?(repo) do
    case :persistent_term.get(backoff_key(repo), nil) do
      at when is_integer(at) ->
        System.monotonic_time(:millisecond) - at < @backoff_ms

      _ ->
        false
    end
  end

  def up do
    Enum.each(statements(), &Ecto.Migration.execute/1)
    :ok
  end

  def down do
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_operators")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_passkeys")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_auth")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_alerts")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_integrations")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_tokens")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_protections")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_sources")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_settings")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_audit")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_dashboard_cards")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_dashboards")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_questions")
    :ok
  end
end
