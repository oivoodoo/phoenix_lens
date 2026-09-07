defmodule PhoenixLens.MCP do
  @moduledoc """
  JSON-RPC 2.0 MCP server for Lens (Streamable HTTP).

  Mounted at `{lens_prefix}/mcp`. Authenticate with a project token from
  Settings → MCP.
  """

  alias PhoenixLens.MCP.Tools

  @protocol_latest "2025-03-26"
  @protocol_supported ~w(2024-11-05 2025-03-26 2025-06-18)
  @server_name "phoenix-lens"

  def protocol_latest, do: @protocol_latest
  def server_name, do: @server_name

  def handle(message, ctx) when is_map(message) do
    id = Map.get(message, "id")
    method = Map.get(message, "method")
    params = Map.get(message, "params") || %{}

    cond do
      not jsonrpc?(message) ->
        {:reply, error_obj(id, -32600, "invalid request")}

      is_nil(method) ->
        {:reply, error_obj(id, -32600, "missing method")}

      notification?(id, method) ->
        :noreply

      true ->
        {:reply, dispatch(id, method, params, ctx)}
    end
  end

  def handle(_, _), do: {:reply, error_obj(nil, -32600, "invalid request")}

  defp dispatch(id, "initialize", params, _ctx) do
    requested = params["protocolVersion"] || params[:protocolVersion]
    version = if requested in @protocol_supported, do: requested, else: @protocol_latest

    result_obj(id, %{
      "protocolVersion" => version,
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{
        "name" => @server_name,
        "version" => app_version()
      },
      "instructions" =>
        "Lens SQL notebook. Run read-only SQL, save questions, pin dashboards, and manage engines. Protected fields are always [redacted]."
    })
  end

  defp dispatch(id, "ping", _params, _ctx), do: result_obj(id, %{})

  defp dispatch(id, "tools/list", _params, _ctx) do
    result_obj(id, %{"tools" => Tools.list()})
  end

  defp dispatch(id, "tools/call", params, ctx) do
    name = params["name"] || params[:name]
    args = params["arguments"] || params[:arguments] || %{}

    case Tools.call(to_string(name || ""), args, ctx) do
      {:ok, value} ->
        text = encode_text(value)

        result_obj(id, %{
          "content" => [%{"type" => "text", "text" => text}],
          "structuredContent" => jsonable(value),
          "isError" => false
        })

      {:error, message} ->
        result_obj(id, %{
          "content" => [%{"type" => "text", "text" => message}],
          "isError" => true
        })
    end
  end

  defp dispatch(id, "notifications/initialized", _params, _ctx), do: result_obj(id, %{})

  defp dispatch(id, method, _params, _ctx) do
    error_obj(id, -32601, "method not found: #{method}")
  end

  defp jsonrpc?(%{"jsonrpc" => "2.0"}), do: true
  defp jsonrpc?(%{jsonrpc: "2.0"}), do: true
  defp jsonrpc?(_), do: false

  defp notification?(nil, "notifications/" <> _), do: true
  defp notification?(_, _), do: false

  defp result_obj(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp error_obj(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    }
  end

  defp encode_text(value) when is_binary(value), do: value

  defp encode_text(value) do
    case Jason.encode(jsonable(value), pretty: true) do
      {:ok, json} -> json
      _ -> inspect(value)
    end
  end

  defp jsonable(%_{} = struct), do: jsonable(Map.from_struct(struct))

  defp jsonable(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), jsonable(v)} end)
  end

  defp jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  defp jsonable(%Date{} = d), do: Date.to_iso8601(d)
  defp jsonable(%Time{} = t), do: Time.to_iso8601(t)
  defp jsonable(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp jsonable(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp jsonable(other), do: other

  defp app_version do
    case Application.spec(:phoenix_lens, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      vsn when is_binary(vsn) -> vsn
      _ -> "0.0.0"
    end
  end
end
