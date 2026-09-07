defmodule PhoenixLens.Policy do
  @moduledoc false

  @type column :: %{
          optional(:name) => String.t(),
          optional(:origin) => String.t() | nil,
          optional(:computed?) => boolean(),
          optional(:sql) => String.t() | nil
        }

  @spec apply([column()], [list()], MapSet.t(String.t()), String.t() | nil) ::
          {[column()], [list()], [String.t()]}
  def apply(columns, rows, protected, sql \\ nil) do
    flags = Enum.map(columns, &protected_column?(&1, protected, sql))

    masked_names =
      columns
      |> Enum.zip(flags)
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(fn {col, _} -> col.name end)

    rows =
      Enum.map(rows, fn row ->
        row
        |> Enum.zip(flags)
        |> Enum.map(fn
          {_value, true} -> :redacted
          {value, false} -> value
        end)
      end)

    {columns, rows, masked_names}
  end

  def protected_set(config, database_id \\ "primary", opts \\ [])

  def protected_set(config, database_id, opts) when is_list(opts) do
    global = names(config.masked_fields)
    by_source = names(Map.get(config.masked_fields_by_source, database_id, []))
    by_source_atom = names(Map.get(config.masked_fields_by_source, to_string(database_id), []))
    redact = names(redact_fields(config))
    tables = opts[:tables] || PhoenixLens.SQL.table_refs(opts[:sql] || "")
    runtime = PhoenixLens.Protection.names(database_id, tables)

    global
    |> MapSet.union(by_source)
    |> MapSet.union(by_source_atom)
    |> MapSet.union(redact)
    |> MapSet.union(runtime)
  end

  def protected_set(config, database_id, sql) when is_binary(sql) do
    protected_set(config, database_id, sql: sql)
  end

  def redact_fields(config) do
    Enum.flat_map(config.databases, fn {_id, db} ->
      case db[:repo] do
        nil -> []
        repo -> schema_redact_fields(repo)
      end
    end)
  end

  def schema_redact_fields(repo) when is_atom(repo) do
    app = repo_otp_app(repo)

    modules =
      case app && :application.get_key(app, :modules) do
        {:ok, list} -> list
        _ -> []
      end

    Enum.flat_map(modules, fn mod ->
      if Code.ensure_loaded?(mod) and function_exported?(mod, :__schema__, 1) do
        redact_field_names(mod)
      else
        []
      end
    end)
  rescue
    _ -> []
  end

  def schema_redact_fields(_), do: []

  defp redact_field_names(mod) do
    fields = mod.__schema__(:fields)

    Enum.filter(fields, fn field ->
      case mod.__schema__(:redact_fields) do
        list when is_list(list) -> field in list
        _ -> false
      end
    end)
  rescue
    _ ->
      # Older Ecto: inspect the struct types via :redact option is stored on the field.
      # `__schema__(:redact_fields)` exists since Ecto 3.5.
      []
  end

  defp repo_otp_app(repo) do
    repo.config()[:otp_app]
  rescue
    _ -> nil
  end

  defp protected_column?(col, protected, sql) do
    name? = protected_name?(col[:name] || col.name, protected)
    origin? = protected_name?(col[:origin], protected)

    computed? =
      Map.get(col, :computed?, is_nil(col[:origin]) and not simple_name_only?(col))

    expr? =
      computed? and
        cond do
          is_binary(col[:sql]) -> identifier_in?(col[:sql], protected)
          is_binary(sql) -> identifier_in?(sql, protected)
          true -> false
        end

    name? or origin? or expr?
  end

  defp simple_name_only?(%{computed?: computed?}), do: computed? == false
  defp simple_name_only?(_), do: false

  defp identifier_in?(nil, _), do: false

  defp identifier_in?(sql, protected) do
    Enum.any?(protected, &PhoenixLens.SQL.contains_identifier?(sql, &1))
  end

  defp protected_name?(nil, _), do: false
  defp protected_name?(name, set), do: MapSet.member?(set, String.downcase(to_string(name)))

  defp names(list) when is_list(list) do
    MapSet.new(list, fn
      atom when is_atom(atom) -> Atom.to_string(atom) |> String.downcase()
      bin when is_binary(bin) -> String.downcase(bin)
      other -> other |> to_string() |> String.downcase()
    end)
  end

  defp names(_), do: MapSet.new()
end
