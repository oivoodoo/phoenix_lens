defmodule PhoenixLensWeb.Helpers do
  @moduledoc false

  use Phoenix.Component

  alias PhoenixLens.Result

  def lens_path(socket_or_conn, rest, params \\ %{})

  def lens_path(socket_or_conn, rest, params) when is_binary(rest) do
    lens_path(socket_or_conn, String.split(rest, "/", trim: true), params)
  end

  def lens_path(socket_or_conn, rest, params) when is_list(rest) do
    prefix = prefix(socket_or_conn)

    path =
      [prefix | rest]
      |> Enum.join("/")
      |> String.replace(~r{/+}, "/")

    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
    append_query(path, params)
  end

  def lens_asset_path(socket_or_conn, file) do
    prefix = prefix(socket_or_conn)
    path = Path.join(prefix, "assets/#{file}") |> String.replace(~r{/+}, "/")
    if String.starts_with?(path, "/"), do: path, else: "/" <> path
  end

  def display_cell(value), do: Result.display_cell(value)

  def greeting_name(nil), do: "there"
  def greeting_name("anonymous"), do: "there"
  def greeting_name("user:" <> id), do: "user #{id}"
  def greeting_name(%{name: name}) when is_binary(name) and name != "", do: name
  def greeting_name(name) when is_binary(name) and name != "", do: name
  def greeting_name(_), do: "there"

  def active_class(current, name) do
    if to_string(current) == to_string(name), do: "active", else: ""
  end

  defp prefix(%Phoenix.LiveView.Socket{} = socket) do
    socket.assigns[:lens_prefix] || "/lens"
  end

  defp prefix(conn) do
    conn.assigns[:lens_prefix] || "/lens"
  end

  defp append_query(path, params) when params == %{} or params == [], do: path

  defp append_query(path, params) do
    filtered =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    case filtered do
      [] -> path
      pairs -> path <> "?" <> URI.encode_query(pairs)
    end
  end
end
