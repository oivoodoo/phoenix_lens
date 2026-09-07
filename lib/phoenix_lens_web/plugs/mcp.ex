defmodule PhoenixLensWeb.Plugs.MCP do
  @moduledoc """
  Streamable HTTP MCP endpoint.

  Put this **after** `Plug.Parsers` in the host endpoint so it runs before the
  browser pipeline (CSRF / `accepts: html`):

      plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
      plug PhoenixLensWeb.Plugs.MCP, path: "/lens/mcp"

  Authenticate with `Authorization: Bearer <secret>` from Settings → MCP.
  """

  @behaviour Plug

  import Plug.Conn

  alias PhoenixLens.{MCP, Tokens}

  def init(opts), do: opts

  def call(conn, opts) do
    if mcp_path?(conn, opts) do
      conn
      |> cors()
      |> dispatch()
      |> halt()
    else
      conn
    end
  end

  def rpc(conn, _params), do: conn |> cors() |> dispatch()
  def sse(conn, _params), do: conn |> cors() |> method_not_allowed()
  def options(conn, _params), do: conn |> cors() |> send_resp(204, "")

  defp dispatch(%{method: "OPTIONS"} = conn), do: send_resp(conn, 204, "")
  defp dispatch(%{method: "GET"} = conn), do: method_not_allowed(conn)

  defp dispatch(%{method: "POST"} = conn) do
    case authenticate(conn) do
      {:ok, conn} -> handle_rpc(conn)
      {:error, conn} -> conn
    end
  end

  defp dispatch(conn), do: method_not_allowed(conn)

  defp authenticate(conn) do
    header =
      case get_req_header(conn, "authorization") do
        [value | _] -> value
        _ -> nil
      end

    case Tokens.authenticate(header) do
      {:ok, actor} ->
        {:ok, assign(conn, :lens_mcp_actor, actor)}

      {:error, _} ->
        conn =
          conn
          |> put_resp_header("www-authenticate", ~s(Bearer realm="phoenix_lens"))
          |> put_resp_content_type("application/json")
          |> send_resp(
            401,
            Jason.encode!(%{"error" => "invalid or missing Lens project token"})
          )

        {:error, conn}
    end
  end

  defp handle_rpc(conn) do
    case decode_body(conn) do
      {:error, _} ->
        json_rpc(conn, 400, %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{"code" => -32700, "message" => "parse error"}
        })

      {:ok, list} when is_list(list) ->
        json_rpc(conn, 400, %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{"code" => -32600, "message" => "batched requests are not supported"}
        })

      {:ok, message} when is_map(message) ->
        ctx = %{actor: conn.assigns[:lens_mcp_actor]}

        conn =
          if message["method"] == "initialize" do
            put_resp_header(conn, "mcp-session-id", session_id())
          else
            conn
          end

        case MCP.handle(message, ctx) do
          :noreply -> send_resp(conn, 202, "")
          {:reply, response} -> json_rpc(conn, 200, response)
        end

      {:ok, _} ->
        json_rpc(conn, 400, %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{"code" => -32600, "message" => "invalid request"}
        })
    end
  end

  defp decode_body(conn) do
    params = conn.body_params

    cond do
      is_map(params) and not match?(%Plug.Conn.Unfetched{}, params) and map_size(params) > 0 ->
        {:ok, params}

      true ->
        case read_body(conn) do
          {:ok, "", _} -> {:error, :empty}
          {:ok, body, _} -> Jason.decode(body)
          _ -> {:error, :empty}
        end
    end
  end

  defp json_rpc(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  defp method_not_allowed(conn) do
    conn
    |> put_resp_header("allow", "POST, OPTIONS")
    |> send_resp(405, "")
  end

  defp cors(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header(
      "access-control-allow-headers",
      "Authorization, Content-Type, Accept, Mcp-Session-Id, MCP-Protocol-Version, Mcp-Protocol-Version"
    )
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-expose-headers", "Mcp-Session-Id")
  end

  defp mcp_path?(conn, opts) do
    want =
      (opts[:path] || "/lens/mcp")
      |> String.split("/", trim: true)

    conn.path_info == want
  end

  defp session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
