defmodule PhoenixLens.Config do
  @moduledoc false

  def get do
    app = Application.get_all_env(:phoenix_lens) |> Map.new()
    databases = databases(app)

    %{
      databases: databases,
      masked_fields: List.wrap(Map.get(app, :masked_fields, [])),
      masked_fields_by_source: Map.get(app, :masked_fields_by_source, %{}) |> stringify_keys(),
      timeout_ms: int(app, :timeout_ms, env_int("PHOENIX_LENS_TIMEOUT_MS", 5_000)),
      max_rows: int(app, :max_rows, env_int("PHOENIX_LENS_MAX_ROWS", 10_000)),
      actor_assign: Map.get(app, :actor_assign, :current_user),
      username: str(app, :username, System.get_env("PHOENIX_LENS_USERNAME")),
      password: str(app, :password, System.get_env("PHOENIX_LENS_PASSWORD")),
      metadata_repo: metadata_repo(app, databases)
    }
  end

  def database(id) do
    id = to_string(id || "primary")
    Map.get(get().databases, id) || Map.get(get().databases, "primary")
  end

  def connection_children do
    get().databases
    |> Enum.flat_map(fn {_id, cfg} ->
      case cfg[:url] do
        url when is_binary(url) and url != "" ->
          name = connection_name(cfg[:id])

          [
            %{
              id: name,
              start: {Postgrex, :start_link, [Keyword.merge(postgrex_opts(url), name: name)]}
            }
          ]

        _ ->
          []
      end
    end)
  end

  def connection_name(id),
    do: Module.concat(PhoenixLens.Connections, Macro.camelize(to_string(id)))

  defp metadata_repo(app, databases) do
    cond do
      repo = app[:repo] ->
        repo

      repo = get_in(databases, ["primary", :repo]) ->
        repo

      true ->
        databases
        |> Map.values()
        |> Enum.find_value(& &1[:repo])
    end
  end

  defp databases(app) do
    cond do
      is_list(app[:databases]) ->
        app[:databases]
        |> Enum.map(&normalize_database/1)
        |> Map.new(fn db -> {db[:id], db} end)

      is_map(app[:databases]) ->
        Map.new(app[:databases], fn {id, cfg} ->
          db = normalize_database({id, cfg})
          {db[:id], db}
        end)

      repo = app[:repo] ->
        %{"primary" => normalize_database({:primary, [repo: repo]})}

      url =
          app[:url] || System.get_env("PHOENIX_LENS_DATABASE_URL") ||
            System.get_env("DATABASE_URL") ->
        %{"primary" => normalize_database({:primary, [url: url]})}

      true ->
        %{}
    end
  end

  defp normalize_database({id, cfg}) when is_list(cfg) do
    Keyword.merge(cfg, id: to_string(id), name: cfg[:name] || titleize(id))
  end

  defp normalize_database({id, cfg}) when is_map(cfg) do
    normalize_database({id, Map.to_list(cfg)})
  end

  defp titleize(id) do
    id
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(_), do: %{}

  defp postgrex_opts(url) do
    uri = URI.parse(url)
    {user, password} = userinfo(uri)

    [
      hostname: uri.host || "localhost",
      port: uri.port || 5432,
      username: user,
      password: password,
      database: database_name(uri.path),
      timeout: 30_000,
      handshake_timeout: 5_000,
      pool_size: 2,
      backoff_type: :stop
    ]
    |> maybe_ssl(uri)
  end

  defp maybe_ssl(opts, %URI{scheme: scheme}) when scheme in ["postgres", "postgresql"], do: opts

  defp maybe_ssl(opts, %URI{query: query}) when is_binary(query) do
    params = URI.decode_query(query)

    if params["sslmode"] in ["require", "verify-full", "verify-ca"] do
      Keyword.put(opts, :ssl, true)
    else
      opts
    end
  end

  defp maybe_ssl(opts, _), do: opts

  defp userinfo(%URI{userinfo: nil}), do: {nil, nil}

  defp userinfo(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {URI.decode(user), nil}
      [user, password] -> {URI.decode(user), URI.decode(password)}
    end
  end

  defp database_name(nil), do: "postgres"
  defp database_name("/"), do: "postgres"
  defp database_name("/" <> name), do: URI.decode(name)
  defp database_name(name), do: name

  defp int(app, key, default) do
    case Map.get(app, key, default) do
      n when is_integer(n) -> n
      n when is_binary(n) -> String.to_integer(n)
      _ -> default
    end
  end

  defp str(app, key, default) do
    case Map.get(app, key, default) do
      n when is_binary(n) and n != "" -> n
      _ -> default
    end
  end

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> String.to_integer(value)
    end
  end
end
