defmodule PhoenixLens.Catalog do
  @moduledoc false

  alias PhoenixLens.{Config, Policy}

  def schemas do
    config = Config.get()
    protected = Policy.protected_set(config)
    repo = config.metadata_repo

    modules =
      case repo do
        nil -> []
        repo -> schema_modules(repo)
      end

    Enum.map(modules, fn mod ->
      source = mod.__schema__(:source)
      prefix = mod.__schema__(:prefix)
      fields = mod.__schema__(:fields)
      types = Map.new(fields, fn f -> {f, inspect(mod.__schema__(:type, f))} end)
      assocs = associations(mod)
      redact = MapSet.new(redact_fields(mod), &to_string/1)

      %{
        module: inspect(mod),
        source: source,
        prefix: prefix,
        fields:
          Enum.map(fields, fn field ->
            name = Atom.to_string(field)

            %{
              name: name,
              type: types[field],
              protected:
                MapSet.member?(protected, String.downcase(name)) or
                  MapSet.member?(redact, name)
            }
          end),
        associations: assocs
      }
    end)
    |> Enum.sort_by(& &1.source)
  end

  defp schema_modules(repo) do
    app = repo.config()[:otp_app]

    modules =
      case app && :application.get_key(app, :modules) do
        {:ok, list} -> list
        _ -> []
      end

    Enum.filter(modules, fn mod ->
      function_exported?(mod, :__schema__, 1) and function_exported?(mod, :__changeset__, 0)
    end)
  rescue
    _ -> []
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
