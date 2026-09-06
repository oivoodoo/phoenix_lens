defmodule PhoenixLens.Migrations do
  @moduledoc """
  Ecto migrations for questions, dashboards, and the audit log.

      defmodule MyApp.Repo.Migrations.AddPhoenixLens do
        use Ecto.Migration

        def up, do: PhoenixLens.Migrations.up()
        def down, do: PhoenixLens.Migrations.down()
      end
  """

  def up do
    Ecto.Migration.execute("""
    CREATE TABLE IF NOT EXISTS phoenix_lens_questions (
      id bigserial PRIMARY KEY,
      name text NOT NULL,
      sql text NOT NULL,
      viz text NOT NULL DEFAULT 'table',
      database_id text NOT NULL DEFAULT 'primary',
      inserted_at timestamp(6) NOT NULL DEFAULT now(),
      updated_at timestamp(6) NOT NULL DEFAULT now()
    )
    """)

    Ecto.Migration.execute("""
    CREATE TABLE IF NOT EXISTS phoenix_lens_dashboards (
      id bigserial PRIMARY KEY,
      name text NOT NULL,
      inserted_at timestamp(6) NOT NULL DEFAULT now(),
      updated_at timestamp(6) NOT NULL DEFAULT now()
    )
    """)

    Ecto.Migration.execute("""
    CREATE TABLE IF NOT EXISTS phoenix_lens_dashboard_cards (
      id bigserial PRIMARY KEY,
      dashboard_id bigint NOT NULL REFERENCES phoenix_lens_dashboards(id) ON DELETE CASCADE,
      question_id bigint NOT NULL REFERENCES phoenix_lens_questions(id) ON DELETE CASCADE,
      position int NOT NULL,
      date_column text,
      inserted_at timestamp(6) NOT NULL DEFAULT now()
    )
    """)

    Ecto.Migration.execute("""
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
    """)

    Ecto.Migration.execute(
      "CREATE INDEX IF NOT EXISTS phoenix_lens_audit_inserted_at_idx ON phoenix_lens_audit (inserted_at DESC)"
    )

    Ecto.Migration.execute(
      "CREATE INDEX IF NOT EXISTS phoenix_lens_audit_query_hash_idx ON phoenix_lens_audit (query_hash)"
    )

    Ecto.Migration.execute(PhoenixLens.Settings.settings_sql())
    Ecto.Migration.execute(PhoenixLens.Settings.settings_alter_sql())
    Ecto.Migration.execute(PhoenixLens.Settings.sources_sql())

    :ok
  end

  def down do
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_sources")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_settings")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_audit")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_dashboard_cards")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_dashboards")
    Ecto.Migration.execute("DROP TABLE IF EXISTS phoenix_lens_questions")
    :ok
  end
end
