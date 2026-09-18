defmodule PhoenixLensWeb.Plugs.Dashboard do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    mount_path = normalize_path(opts[:mount_path] || "/lens")
    config = PhoenixLens.Config.get()

    conn =
      conn
      |> assign(:lens_mount_path, mount_path)
      |> assign(:lens_prefix, prefix_from_conn(conn, mount_path))
      |> assign(:lens_databases, Map.values(config.databases) |> Enum.sort_by(& &1[:id]))
      |> assign(:lens_standalone, PhoenixLens.Standalone.enabled?())

    if skip_csrf?(conn) do
      conn
      |> assign(:lens_actor, actor(conn, config))
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
    else
      conn
      |> maybe_basic_auth(opts, config)
      |> maybe_halt()
      |> maybe_operator(opts)
      |> assign_actor(config)
      |> maybe_lock()
    end
  end

  def session(conn) do
    %{
      "lens_prefix" => conn.assigns[:lens_prefix],
      "lens_actor" => conn.assigns[:lens_actor],
      "lens_standalone" => conn.assigns[:lens_standalone] == true,
      "lens_unlocked" => Plug.Conn.get_session(conn, :lens_unlocked) == true,
      "lens_operator_id" => Plug.Conn.get_session(conn, :lens_operator_id),
      "lens_operator" => Plug.Conn.get_session(conn, :lens_operator),
      "lens_databases" =>
        Enum.map(conn.assigns[:lens_databases] || [], fn db ->
          %{id: db[:id], name: db[:name]}
        end)
    }
  end

  def prefix_from_conn(conn, mount_path) do
    mount_parts = String.split(mount_path || "", "/", trim: true)
    full_path = conn.script_name ++ conn.path_info

    prefix_parts =
      case mount_parts do
        [] ->
          conn.script_name

        _ ->
          case find_subsequence(full_path, mount_parts) do
            nil -> conn.script_name ++ mount_parts
            idx -> Enum.take(full_path, idx + length(mount_parts))
          end
      end

    case prefix_parts do
      [] -> ""
      parts -> "/" <> Enum.join(parts, "/")
    end
  end

  defp assign_actor(%{halted: true} = conn, _config), do: conn

  defp assign_actor(conn, config) do
    assign(conn, :lens_actor, actor(conn, config))
  end

  defp actor(conn, config) do
    conn.assigns[config.actor_assign] || conn.assigns[:lens_actor]
  end

  defp skip_csrf?(conn), do: "assets" in conn.path_info or "mcp" in conn.path_info

  defp maybe_basic_auth(conn, opts, config) do
    username = opts[:username] || config.username
    password = opts[:password] || config.password

    if is_binary(password) and password != "" do
      Plug.BasicAuth.basic_auth(conn, username: username || "", password: password)
    else
      conn
    end
  end

  defp maybe_halt(%{halted: true} = conn), do: conn

  defp maybe_halt(%{assigns: %{lens_databases: []}} = conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(
      500,
      "PhoenixLens is not configured. Set config :phoenix_lens, repo: MyApp.Repo"
    )
    |> halt()
  end

  defp maybe_halt(conn), do: conn

  defp maybe_operator(%{halted: true} = conn, _opts), do: conn

  defp maybe_operator(conn, opts) do
    cond do
      opts[:skip_operator] ->
        conn

      not PhoenixLens.Operator.required?() ->
        conn

      skip_operator?(conn) ->
        conn

      operator = Plug.Conn.get_session(conn, :lens_operator) ->
        conn
        |> assign(:current_user, "operator:#{operator}")
        |> assign(:lens_operator, operator)

      PhoenixLens.Operator.configured?() ->
        redirect_gate(conn, "/login")

      true ->
        redirect_gate(conn, "/setup")
    end
  end

  defp maybe_lock(%{halted: true} = conn), do: conn

  defp maybe_lock(conn) do
    cond do
      skip_lock?(conn) ->
        conn

      not PhoenixLens.Auth.required?() ->
        conn

      get_session(conn, :lens_unlocked) == true ->
        conn

      true ->
        prefix = conn.assigns[:lens_prefix] || "/lens"

        conn
        |> put_resp_header("location", prefix <> "/unlock")
        |> send_resp(302, "")
        |> halt()
    end
  end

  defp skip_lock?(conn) do
    skip_csrf?(conn) or "unlock" in conn.path_info or skip_operator?(conn)
  end

  defp skip_operator?(conn) do
    Enum.any?(conn.path_info, &(&1 in ["setup", "login", "session", "logout"]))
  end

  defp redirect_gate(conn, rest) do
    prefix = conn.assigns[:lens_prefix] || "/lens"

    conn
    |> put_resp_header("location", prefix <> rest)
    |> send_resp(302, "")
    |> halt()
  end

  defp find_subsequence(_list, []), do: 0

  defp find_subsequence(list, sub) do
    last = length(list) - length(sub)

    if last < 0 do
      nil
    else
      Enum.find_value(0..last, fn i ->
        if Enum.slice(list, i, length(sub)) == sub, do: i
      end)
    end
  end

  defp normalize_path("/"), do: ""
  defp normalize_path(path), do: String.trim_trailing(path, "/")
end
