defmodule PhoenixLens.Integrations do
  @moduledoc """
  Email (SMTP) and webhook channels for alerts.
  """

  alias PhoenixLens.{Config, Error}

  @kinds ~w(email webhook)

  def kinds, do: @kinds

  def table_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_integrations (
      id bigserial PRIMARY KEY,
      kind text NOT NULL,
      name text NOT NULL,
      config text NOT NULL DEFAULT '{}',
      enabled boolean NOT NULL DEFAULT true,
      error text,
      inserted_at timestamp(6) NOT NULL DEFAULT now(),
      updated_at timestamp(6) NOT NULL DEFAULT now()
    )
    """
  end

  def ensure_table do
    case repo() do
      nil ->
        :ok

      repo ->
        repo.query!(table_sql(), [], log: false)
        :ok
    end
  rescue
    _ -> :ok
  end

  def list(kind \\ nil) do
    ensure_table()

    rows =
      query_maps("""
      SELECT id, kind, name, config, enabled, error, inserted_at, updated_at
      FROM phoenix_lens_integrations
      ORDER BY kind, id
      """)

    rows =
      if is_binary(kind) and kind != "" do
        Enum.filter(rows, &(&1["kind"] == kind))
      else
        rows
      end

    Enum.map(rows, &decode/1)
  rescue
    _ -> []
  end

  def webhooks, do: list("webhook") |> Enum.filter(& &1["enabled"])

  def email do
    case Enum.find(list("email"), & &1["enabled"]) do
      nil -> env_email()
      row -> row
    end
  end

  def get(id) do
    ensure_table()

    case query_maps(
           "SELECT id, kind, name, config, enabled, error, inserted_at, updated_at FROM phoenix_lens_integrations WHERE id = $1",
           [to_int(id)]
         ) do
      [row] -> {:ok, decode(row)}
      [] -> {:error, %Error{message: "integration not found", kind: :config}}
    end
  end

  def save_email(attrs) when is_map(attrs) do
    with {:ok, cfg} <- normalize_email(attrs) do
      upsert("email", "SMTP", cfg)
    end
  end

  def add_webhook(attrs) when is_map(attrs) do
    with {:ok, name, cfg} <- normalize_webhook(attrs) do
      ensure_table()

      case repo() do
        nil ->
          {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}

        repo ->
          %{rows: [[id]]} =
            repo.query!(
              """
              INSERT INTO phoenix_lens_integrations (kind, name, config, enabled, inserted_at, updated_at)
              VALUES ('webhook', $1, $2, TRUE, NOW(), NOW())
              RETURNING id
              """,
              [name, Jason.encode!(cfg)],
              log: false
            )

          get(id)
      end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def delete(id) do
    ensure_table()

    case repo() do
      nil ->
        {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}

      repo ->
        repo.query!("DELETE FROM phoenix_lens_integrations WHERE id = $1", [to_int(id)],
          log: false
        )

        :ok
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def public(row) when is_map(row) do
    cfg = row["config"] || %{}

    config =
      cfg
      |> Map.drop(["password", "token"])
      |> Map.put("has_password", present?(cfg["password"]))
      |> Map.put("has_token", present?(cfg["token"]))
      |> Map.update("url", "", &redact_url/1)

    %{
      "id" => row["id"],
      "kind" => row["kind"],
      "name" => row["name"],
      "enabled" => row["enabled"],
      "error" => row["error"],
      "config" => config
    }
  end

  def redact_url(nil), do: ""

  def redact_url(url) when is_binary(url) do
    String.replace(url, ~r{(://[^:/?#]+:)([^@]+)(@)}, "\\1••••\\3")
  end

  def redact_url(_), do: ""

  defp upsert(kind, name, cfg) do
    ensure_table()

    case repo() do
      nil ->
        {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}

      repo ->
        existing = Enum.find(list(kind), &(&1["kind"] == kind))
        json = Jason.encode!(cfg)

        cond do
          existing ->
            merged = merge_secrets(existing["config"] || %{}, cfg)
            json = Jason.encode!(merged)

            repo.query!(
              """
              UPDATE phoenix_lens_integrations
              SET name = $2, config = $3, enabled = TRUE, error = NULL, updated_at = NOW()
              WHERE id = $1
              """,
              [existing["id"], name, json],
              log: false
            )

            get(existing["id"])

          true ->
            %{rows: [[id]]} =
              repo.query!(
                """
                INSERT INTO phoenix_lens_integrations (kind, name, config, enabled, inserted_at, updated_at)
                VALUES ($1, $2, $3, TRUE, NOW(), NOW())
                RETURNING id
                """,
                [kind, name, json],
                log: false
              )

            get(id)
        end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  defp merge_secrets(old, new) do
    new
    |> keep_secret(old, "password")
    |> keep_secret(old, "token")
  end

  defp keep_secret(cfg, old, key) do
    val = cfg[key]

    if blank?(val) or val in ["••••", "********"] do
      Map.put(cfg, key, old[key])
    else
      cfg
    end
  end

  defp normalize_email(attrs) do
    host = trim(attrs[:host] || attrs["host"])
    from = trim(attrs[:from] || attrs["from"])
    port = parse_port(attrs[:port] || attrs["port"] || 587)

    cond do
      host == "" ->
        {:error, %Error{message: "SMTP host is required", kind: :config}}

      from == "" ->
        {:error, %Error{message: "From address is required", kind: :config}}

      is_nil(port) ->
        {:error, %Error{message: "SMTP port is invalid", kind: :config}}

      true ->
        {:ok,
         %{
           "host" => host,
           "port" => port,
           "tls" => truthy?(attrs[:tls] || attrs["tls"], true),
           "username" => trim(attrs[:username] || attrs["username"]),
           "password" => trim(attrs[:password] || attrs["password"]),
           "from" => from
         }}
    end
  end

  defp normalize_webhook(attrs) do
    name = trim(attrs[:name] || attrs["name"])
    url = trim(attrs[:url] || attrs["url"])
    auth = trim(attrs[:auth] || attrs["auth"] || "none") |> String.downcase()
    token = trim(attrs[:token] || attrs["token"])

    cond do
      name == "" ->
        {:error, %Error{message: "webhook name is required", kind: :config}}

      not valid_url?(url) ->
        {:error, %Error{message: "webhook URL must be http or https", kind: :config}}

      auth not in ["none", "bearer", "header"] ->
        {:error, %Error{message: "auth must be none, bearer, or header", kind: :config}}

      auth != "none" and token == "" ->
        {:error, %Error{message: "token is required for this auth method", kind: :config}}

      true ->
        {:ok, name,
         %{
           "url" => url,
           "auth" => auth,
           "token" => token,
           "header" => trim(attrs[:header] || attrs["header"] || "X-Api-Key")
         }}
    end
  end

  defp env_email do
    smtp = Application.get_env(:phoenix_lens, :smtp) || []

    host = smtp[:host] || smtp["host"]
    from = smtp[:from] || smtp["from"]

    if is_binary(host) and host != "" and is_binary(from) and from != "" do
      %{
        "id" => nil,
        "kind" => "email",
        "name" => "SMTP",
        "enabled" => true,
        "error" => nil,
        "config" => %{
          "host" => host,
          "port" => smtp[:port] || smtp["port"] || 587,
          "tls" => smtp[:tls] || smtp["tls"] || true,
          "username" => smtp[:username] || smtp["username"] || "",
          "password" => smtp[:password] || smtp["password"] || "",
          "from" => from
        }
      }
    end
  end

  defp decode(row) do
    cfg =
      case Jason.decode(row["config"] || "{}") do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    Map.put(row, "config", cfg)
  end

  defp valid_url?(url) do
    is_binary(url) and String.starts_with?(url, ["http://", "https://"]) and
      String.length(url) < 2000
  end

  defp parse_port(n) when is_integer(n) and n > 0 and n < 65536, do: n

  defp parse_port(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {int, ""} -> parse_port(int)
      _ -> nil
    end
  end

  defp parse_port(_), do: nil

  defp truthy?(val, default) do
    case val do
      true -> true
      false -> false
      "true" -> true
      "on" -> true
      "1" -> true
      "false" -> false
      "off" -> false
      "0" -> false
      _ -> default
    end
  end

  defp present?(v), do: is_binary(v) and String.trim(v) != ""
  defp blank?(v), do: is_nil(v) or v == ""
  defp trim(nil), do: ""
  defp trim(v), do: v |> to_string() |> String.trim()

  defp query_maps(sql, params \\ []) do
    case repo() do
      nil ->
        []

      repo ->
        %{rows: rows, columns: columns} = repo.query!(sql, params, log: false)

        Enum.map(rows, fn row ->
          columns |> Enum.map(&to_string/1) |> Enum.zip(row) |> Map.new()
        end)
    end
  end

  defp repo, do: Config.get().metadata_repo
  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)
end
