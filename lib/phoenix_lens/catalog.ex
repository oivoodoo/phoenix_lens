defmodule PhoenixLens.Catalog do
  @moduledoc false

  alias PhoenixLens.{Config, Policy, Protection}

  def schemas do
    config = Config.get()
    protected = Policy.protected_set(config)
    repo = config.metadata_repo

    modules =
      case repo do
        nil -> []
        repo -> schema_modules(repo)
      end

    Enum.map(modules, fn mod -> schema_entry(mod, protected) end)
    |> Enum.sort_by(& &1.source)
  end

  @doc """
  Tables to show in Data: Ecto schemas when loaded, plus public Postgres tables.
  """
  def browse do
    config = Config.get()
    protected = Policy.protected_set(config)
    ecto = schemas()
    by_source = Map.new(ecto, fn s -> {String.downcase(s.source), s} end)

    Enum.reduce(database_tables(), by_source, fn table, acc ->
      key = String.downcase(table.name)

      Map.update(acc, key, db_entry(table, protected), fn existing ->
        merge_fields(existing, table, protected)
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.source)
  end

  def database_tables do
    if PhoenixLens.Settings.engine() == :duckdb do
      duckdb_tables()
    else
      postgres_tables()
    end
  rescue
    _ -> postgres_tables()
  end

  defp duckdb_tables do
    tables = PhoenixLens.DuckDB.Server.tables()

    if tables == [] do
      postgres_tables()
    else
      tables
    end
  end

  defp postgres_tables do
    repo = Config.get().metadata_repo

    if is_nil(repo) do
      []
    else
      case repo.query(
             """
             SELECT table_name, column_name, data_type
             FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name NOT LIKE 'phoenix_lens_%'
               AND table_name <> 'schema_migrations'
             ORDER BY table_name, ordinal_position
             """,
             [],
             log: false
           ) do
        {:ok, %{rows: rows}} ->
          rows
          |> Enum.group_by(fn [table, _, _] -> table end)
          |> Enum.map(fn {table, cols} ->
            %{
              name: table,
              columns:
                Enum.map(cols, fn [_, name, type] ->
                  %{name: name, type: type}
                end)
            }
          end)

        _ ->
          []
      end
    end
  rescue
    _ -> []
  end

  defp schema_entry(mod, protected) do
    source = mod.__schema__(:source)
    fields = mod.__schema__(:fields)
    types = Map.new(fields, fn f -> {f, inspect(mod.__schema__(:type, f))} end)
    redact = MapSet.new(redact_fields(mod), &to_string/1)

    %{
      module: inspect(mod),
      source: source,
      prefix: mod.__schema__(:prefix),
      fields:
        Enum.map(fields, fn field ->
          name = Atom.to_string(field)

          %{
            name: name,
            type: types[field],
            protected:
              MapSet.member?(protected, String.downcase(name)) or MapSet.member?(redact, name) or
                Protection.column_protected?(name, "primary", source)
          }
        end),
      associations: associations(mod)
    }
  end

  defp db_entry(table, protected) do
    %{
      module: table_module(table),
      source: table.name,
      prefix: table[:schema],
      fields:
        Enum.map(table.columns, fn col ->
          %{
            name: col.name,
            type: col.type,
            protected:
              MapSet.member?(protected, String.downcase(col.name)) or
                Protection.column_protected?(col.name, table[:database] || "primary", table.name)
          }
        end),
      associations: []
    }
  end

  defp table_module(%{database: db}) when is_binary(db) and db != "", do: db
  defp table_module(_), do: "postgres"

  defp merge_fields(existing, table, protected) do
    have = MapSet.new(existing.fields, & &1.name)

    extra =
      table.columns
      |> Enum.reject(&MapSet.member?(have, &1.name))
      |> Enum.map(fn col ->
        %{
          name: col.name,
          type: col.type,
          protected: MapSet.member?(protected, String.downcase(col.name))
        }
      end)

    %{existing | fields: existing.fields ++ extra}
  end

  defp schema_modules(repo) do
    app = repo_otp_app(repo)

    modules =
      case app && :application.get_key(app, :modules) do
        {:ok, list} -> list
        _ -> []
      end

    Enum.filter(modules, fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :__schema__, 1) and
        is_binary(mod.__schema__(:source))
    end)
  rescue
    _ -> []
  end

  defp repo_otp_app(repo) when is_atom(repo) do
    repo.config()[:otp_app]
  rescue
    _ -> nil
  end

  defp associations(mod) do
    mod.__schema__(:associations)
    |> Enum.map(fn name ->
      assoc = mod.__schema__(:association, name)

      %{
        name: Atom.to_string(name),
        type: assoc.__struct__ |> Module.split() |> List.last(),
        related: inspect(Map.get(assoc, :related))
      }
    end)
  rescue
    _ -> []
  end

  defp redact_fields(mod) do
    mod.__schema__(:redact_fields)
  rescue
    _ -> []
  end
end
