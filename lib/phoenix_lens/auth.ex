defmodule PhoenixLens.Auth do
  @moduledoc """
  Optional Lens lock: authenticator-app TOTP and WebAuthn passkeys.

  When either is enabled, the UI asks for a second factor at `/unlock`.
  MCP tokens are unaffected. Disable everything from IEx with `reset!/0`
  if you lock yourself out.
  """

  alias PhoenixLens.{Config, Error}

  def auth_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_auth (
      id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
      totp_secret text,
      totp_enabled boolean NOT NULL DEFAULT false,
      totp_pending_secret text,
      updated_at timestamp(6) NOT NULL DEFAULT now()
    )
    """
  end

  def passkeys_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_passkeys (
      id bigserial PRIMARY KEY,
      name text NOT NULL,
      credential_id text NOT NULL UNIQUE,
      public_key bytea NOT NULL,
      sign_count bigint NOT NULL DEFAULT 0,
      inserted_at timestamp(6) NOT NULL DEFAULT now()
    )
    """
  end

  def ensure_tables do
    case repo() do
      nil ->
        :ok

      repo ->
        repo.query!(auth_sql(), [], log: false)
        repo.query!(passkeys_sql(), [], log: false)
        :ok
    end
  rescue
    _ -> :ok
  end

  def required? do
    totp_enabled?() or passkeys() != []
  end

  def totp_enabled? do
    case row() do
      %{"totp_enabled" => true, "totp_secret" => secret}
      when is_binary(secret) and secret != "" ->
        true

      _ ->
        false
    end
  end

  def totp_pending? do
    case row() do
      %{"totp_pending_secret" => secret} when is_binary(secret) and secret != "" -> true
      _ -> false
    end
  end

  def start_totp do
    ensure_tables()
    secret = NimbleTOTP.secret()
    encoded = Base.encode32(secret, padding: false)

    with :ok <- upsert_auth(%{"totp_pending_secret" => encoded}) do
      {:ok, %{secret: encoded, uri: otpauth_uri(encoded), svg: qr_svg(encoded)}}
    end
  end

  def confirm_totp(code) do
    case row() do
      %{"totp_pending_secret" => pending} when is_binary(pending) and pending != "" ->
        if valid_code?(pending, code) do
          upsert_auth(%{
            "totp_secret" => pending,
            "totp_enabled" => true,
            "totp_pending_secret" => nil
          })
        else
          {:error, %Error{message: "That code is not valid", kind: :config}}
        end

      _ ->
        {:error, %Error{message: "Start authenticator setup first", kind: :config}}
    end
  end

  def disable_totp(code) do
    case row() do
      %{"totp_enabled" => true, "totp_secret" => secret} ->
        if valid_code?(secret, code) do
          upsert_auth(%{
            "totp_secret" => nil,
            "totp_enabled" => false,
            "totp_pending_secret" => nil
          })
        else
          {:error, %Error{message: "That code is not valid", kind: :config}}
        end

      _ ->
        {:error, %Error{message: "Authenticator is not enabled", kind: :config}}
    end
  end

  def verify_totp(code) do
    case row() do
      %{"totp_enabled" => true, "totp_secret" => secret} ->
        valid_code?(secret, code)

      _ ->
        false
    end
  end

  def cancel_totp_setup do
    upsert_auth(%{"totp_pending_secret" => nil})
  end

  def otpauth_uri(secret) when is_binary(secret) do
    NimbleTOTP.otpauth_uri("Lens:operator", decode_secret(secret), issuer: "Lens")
  end

  def qr_svg(secret) when is_binary(secret) do
    secret
    |> otpauth_uri()
    |> EQRCode.encode()
    |> EQRCode.svg(width: 176, color: "#3f4d67")
  end

  def passkeys do
    ensure_tables()

    query_maps("""
    SELECT id, name, credential_id, sign_count, inserted_at
    FROM phoenix_lens_passkeys
    ORDER BY inserted_at DESC
    """)
  rescue
    _ -> []
  end

  def registration_challenge(origin) when is_binary(origin) do
    Wax.new_registration_challenge(
      origin: origin,
      rp_id: :auto,
      attestation: "none",
      user_verification: "preferred"
    )
  end

  def authentication_challenge(origin) when is_binary(origin) do
    allow =
      Enum.map(passkey_records(), fn rec ->
        {rec.raw_id, rec.cose}
      end)

    Wax.new_authentication_challenge(
      origin: origin,
      rp_id: :auto,
      user_verification: "preferred",
      allow_credentials: allow
    )
  end

  def register_passkey(name, attrs, challenge) when is_map(attrs) do
    name = name |> to_string() |> String.trim()
    name = if name == "", do: "Passkey", else: name

    attestation = b64(attrs["attestationObject"] || attrs[:attestationObject])
    client_data = b64(attrs["clientDataJSON"] || attrs[:clientDataJSON])
    raw_id = b64(attrs["rawId"] || attrs[:rawId])

    with {:ok, {auth_data, _att}} <- Wax.register(attestation, client_data, challenge) do
      cose = auth_data.attested_credential_data.credential_public_key
      cred_id = auth_data.attested_credential_data.credential_id || raw_id
      encoded_id = Base.url_encode64(cred_id, padding: false)
      blob = :erlang.term_to_binary(cose)

      ensure_tables()
      repo = repo()

      repo.query!(
        """
        INSERT INTO phoenix_lens_passkeys (name, credential_id, public_key, sign_count, inserted_at)
        VALUES ($1, $2, $3, 0, NOW())
        """,
        [String.slice(name, 0, 80), encoded_id, blob],
        log: false
      )

      {:ok, encoded_id}
    else
      {:error, reason} -> {:error, %Error{message: format_wax(reason), kind: :config}}
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def authenticate_passkey(attrs, challenge) when is_map(attrs) do
    raw_id = b64(attrs["rawId"] || attrs[:rawId])
    auth_data = b64(attrs["authenticatorData"] || attrs[:authenticatorData])
    sig = b64(attrs["signature"] || attrs[:signature])
    client_data = b64(attrs["clientDataJSON"] || attrs[:clientDataJSON])

    case Wax.authenticate(raw_id, auth_data, sig, client_data, challenge) do
      {:ok, _} ->
        touch_passkey(raw_id)
        :ok

      {:error, reason} ->
        {:error, %Error{message: format_wax(reason), kind: :config}}
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def revoke_passkey(id) do
    ensure_tables()
    repo().query!("DELETE FROM phoenix_lens_passkeys WHERE id = $1", [to_int(id)], log: false)
    :ok
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def reset! do
    ensure_tables()

    case repo() do
      nil ->
        :ok

      repo ->
        repo.query!("DELETE FROM phoenix_lens_passkeys", [], log: false)
        repo.query!("DELETE FROM phoenix_lens_auth", [], log: false)
        :ok
    end
  end

  @tickets :phoenix_lens_unlock_tickets

  def issue_unlock_ticket(opts \\ []) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    :ets.insert(
      tickets_table(),
      {token, %{at: System.system_time(:second), to: opts[:to], flash: opts[:flash]}}
    )

    token
  end

  def consume_unlock_ticket(token) when is_binary(token) do
    now = System.system_time(:second)

    case :ets.take(tickets_table(), token) do
      [{^token, %{at: at} = meta}] when now - at < 60 -> {:ok, meta}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  def consume_unlock_ticket(_), do: :error

  defp tickets_table do
    case :ets.whereis(@tickets) do
      :undefined -> :ets.new(@tickets, [:named_table, :public, :set, read_concurrency: true])
      tid -> tid
    end
  rescue
    ArgumentError -> @tickets
  end

  def challenge_bytes(%{bytes: bytes}), do: Base.encode64(bytes)
  def challenge_bytes(_), do: nil

  def rp_id(origin) when is_binary(origin) do
    origin
    |> URI.parse()
    |> Map.get(:host)
    |> Kernel.||("localhost")
  end

  @doc """
  WebAuthn origin from the browser (`window.location.origin`), falling back
  to the endpoint URL. Must match the page origin exactly, including port.
  """
  def origin_from(origin, fallback) when is_binary(fallback) do
    uri = URI.parse(to_string(origin || ""))

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      default = if uri.scheme == "https", do: 443, else: 80

      if is_integer(uri.port) and uri.port != default do
        "#{uri.scheme}://#{uri.host}:#{uri.port}"
      else
        "#{uri.scheme}://#{uri.host}"
      end
    else
      String.trim_trailing(fallback, "/")
    end
  end

  defp passkey_records do
    ensure_tables()

    query_maps("SELECT credential_id, public_key FROM phoenix_lens_passkeys")
    |> Enum.flat_map(fn row ->
      try do
        raw = Base.url_decode64!(row["credential_id"], padding: false)
        cose = :erlang.binary_to_term(row["public_key"], [:safe])
        [%{raw_id: raw, cose: cose}]
      rescue
        _ -> []
      end
    end)
  end

  defp touch_passkey(raw_id) do
    encoded = Base.url_encode64(raw_id, padding: false)

    repo().query!(
      "UPDATE phoenix_lens_passkeys SET sign_count = sign_count + 1 WHERE credential_id = $1",
      [encoded],
      log: false
    )
  rescue
    _ -> :ok
  end

  defp valid_code?(secret, code) do
    code = code |> to_string() |> String.replace(~r/\s+/, "")
    NimbleTOTP.valid?(decode_secret(secret), code)
  rescue
    _ -> false
  end

  defp decode_secret(secret) do
    case Base.decode32(secret, padding: false) do
      {:ok, bin} -> bin
      :error -> Base.decode32!(secret, padding: true)
    end
  end

  defp b64(nil), do: ""

  defp b64(bin) when is_binary(bin) do
    padded =
      case rem(byte_size(bin), 4) do
        0 -> bin
        n -> bin <> String.duplicate("=", 4 - n)
      end

    case Base.url_decode64(padded) do
      {:ok, raw} -> raw
      :error -> Base.decode64!(padded)
    end
  rescue
    _ -> bin
  end

  defp upsert_auth(fields) do
    ensure_tables()
    repo = repo()

    if is_nil(repo) do
      {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
    else
      current = row() || %{}
      secret = Map.get(fields, "totp_secret", current["totp_secret"])
      enabled = Map.get(fields, "totp_enabled", current["totp_enabled"] || false)
      pending = Map.get(fields, "totp_pending_secret", current["totp_pending_secret"])

      repo.query!(
        """
        INSERT INTO phoenix_lens_auth (id, totp_secret, totp_enabled, totp_pending_secret, updated_at)
        VALUES (1, $1, $2, $3, NOW())
        ON CONFLICT (id) DO UPDATE SET
          totp_secret = EXCLUDED.totp_secret,
          totp_enabled = EXCLUDED.totp_enabled,
          totp_pending_secret = EXCLUDED.totp_pending_secret,
          updated_at = NOW()
        """,
        [secret, enabled, pending],
        log: false
      )

      :ok
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  defp row do
    ensure_tables()

    case query_maps(
           "SELECT totp_secret, totp_enabled, totp_pending_secret FROM phoenix_lens_auth WHERE id = 1"
         ) do
      [row] -> row
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp format_wax(%_{} = error), do: Exception.message(error)
  defp format_wax(reason) when is_binary(reason), do: reason
  defp format_wax(reason), do: inspect(reason)

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
