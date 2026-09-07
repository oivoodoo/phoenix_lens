defmodule PhoenixLens.Tokens do
  @moduledoc """
  Project tokens for the Lens MCP endpoint.

  The public **token id** (`plt_…`) is safe to list. The secret (`lns_…`) is
  shown once and stored only as a SHA-256 hash. Authenticate with
  `Authorization: Bearer <secret>` (optionally `plt_…:lns_…`).
  """

  alias PhoenixLens.{Config, Error}

  @id_prefix "plt_"
  @secret_prefix "lns_"

  def table_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_tokens (
      id bigserial PRIMARY KEY,
      token_id text NOT NULL UNIQUE,
      name text NOT NULL,
      token_hash text NOT NULL UNIQUE,
      token_prefix text NOT NULL,
      last_used_at timestamp(6),
      revoked_at timestamp(6),
      inserted_at timestamp(6) NOT NULL DEFAULT now()
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

  def list do
    ensure_table()

    query_maps("""
    SELECT id, token_id, name, token_prefix, last_used_at, revoked_at, inserted_at
    FROM phoenix_lens_tokens
    WHERE revoked_at IS NULL
    ORDER BY inserted_at DESC
    """)
  rescue
    _ -> []
  end

  def create(name) do
    name = name |> to_string() |> String.trim()

    cond do
      name == "" ->
        {:error, %Error{message: "name is required", kind: :config}}

      String.length(name) > 80 ->
        {:error, %Error{message: "name is too long", kind: :config}}

      true ->
        ensure_table()

        case repo() do
          nil ->
            {:error,
             %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}

          repo ->
            token_id = @id_prefix <> random_id()
            secret = @secret_prefix <> random_secret()
            hash = hash_secret(secret)
            prefix = String.slice(secret, 0, 12)

            %{rows: [[id]]} =
              repo.query!(
                """
                INSERT INTO phoenix_lens_tokens
                  (token_id, name, token_hash, token_prefix, inserted_at)
                VALUES ($1, $2, $3, $4, NOW())
                RETURNING id
                """,
                [token_id, name, hash, prefix],
                log: false
              )

            {:ok,
             %{
               id: id,
               token_id: token_id,
               name: name,
               secret: secret,
               prefix: prefix
             }}
        end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def revoke(id) do
    ensure_table()

    case repo() do
      nil ->
        {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}

      repo ->
        repo.query!(
          "UPDATE phoenix_lens_tokens SET revoked_at = NOW() WHERE id = $1 AND revoked_at IS NULL",
          [to_int(id)],
          log: false
        )

        :ok
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def authenticate(nil), do: {:error, :unauthorized}
  def authenticate(""), do: {:error, :unauthorized}

  def authenticate(bearer) when is_binary(bearer) do
    ensure_table()

    case parse_bearer(bearer) do
      {:ok, token_id, secret} ->
        lookup(token_id, secret)

      :error ->
        {:error, :unauthorized}
    end
  end

  def authenticate(_), do: {:error, :unauthorized}

  def parse_bearer("Bearer " <> rest), do: parse_bearer(String.trim(rest))
  def parse_bearer("bearer " <> rest), do: parse_bearer(String.trim(rest))

  def parse_bearer(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        :error

      String.contains?(value, ":") ->
        case String.split(value, ":", parts: 2) do
          [token_id, secret] -> {:ok, token_id, secret}
          _ -> :error
        end

      String.starts_with?(value, @secret_prefix) ->
        {:ok, nil, value}

      true ->
        {:ok, nil, value}
    end
  end

  def parse_bearer(_), do: :error

  def hash_secret(secret) when is_binary(secret) do
    :crypto.hash(:sha256, secret) |> Base.encode16(case: :lower)
  end

  defp lookup(token_id, secret) do
    hash = hash_secret(secret)

    sql =
      if is_binary(token_id) and token_id != "" do
        {"SELECT id, token_id, name FROM phoenix_lens_tokens WHERE token_hash = $1 AND token_id = $2 AND revoked_at IS NULL",
         [hash, token_id]}
      else
        {"SELECT id, token_id, name FROM phoenix_lens_tokens WHERE token_hash = $1 AND revoked_at IS NULL",
         [hash]}
      end

    {query, params} = sql

    case query_maps(query, params) do
      [row] ->
        touch(row["id"])

        {:ok,
         %{
           id: row["token_id"],
           name: row["name"],
           kind: :mcp,
           db_id: row["id"]
         }}

      _ ->
        {:error, :unauthorized}
    end
  rescue
    _ -> {:error, :unauthorized}
  end

  defp touch(id) do
    repo().query!(
      "UPDATE phoenix_lens_tokens SET last_used_at = NOW() WHERE id = $1",
      [id],
      log: false
    )
  rescue
    _ -> :ok
  end

  defp random_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp random_secret do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end

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
