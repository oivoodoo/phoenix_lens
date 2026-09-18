defmodule PhoenixLens.Operator do
  @moduledoc false

  # Standalone-only operator account. Host apps that mount Lens keep using
  # their own pipeline; this table is never consulted unless standalone is on.

  alias PhoenixLens.{Alerts.Mailer, Config, Error, Integrations}

  @iterations 210_000
  @digest_size 32
  @code_ttl 600
  @ticket_ttl 60
  @codes :phoenix_lens_operator_codes
  @tickets :phoenix_lens_operator_tickets
  @username ~r/\A[a-zA-Z0-9][a-zA-Z0-9._-]{2,39}\z/
  @email ~r/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  def table_sql do
    """
    CREATE TABLE IF NOT EXISTS phoenix_lens_operators (
      id bigserial PRIMARY KEY,
      username text NOT NULL UNIQUE,
      password_hash text NOT NULL,
      email text,
      email_verified_at timestamp(6),
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

  def required? do
    PhoenixLens.Standalone.enabled?()
  end

  def configured? do
    ensure_table()
    match?([_ | _], query_maps("SELECT id FROM phoenix_lens_operators LIMIT 1"))
  rescue
    _ -> false
  end

  def get do
    ensure_table()

    case query_maps("""
         SELECT id, username, password_hash, email, email_verified_at
         FROM phoenix_lens_operators
         ORDER BY id ASC
         LIMIT 1
         """) do
      [row] -> row
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def smtp_configured? do
    case Integrations.email() do
      %{"config" => cfg} when is_map(cfg) ->
        present?(cfg["host"] || cfg[:host]) and present?(cfg["from"] || cfg[:from])

      _ ->
        false
    end
  end

  def email_2fa?(operator \\ get()) do
    smtp_configured?() and present?(operator && operator["email"]) and
      not is_nil(operator && operator["email_verified_at"])
  end

  def validate_attrs(attrs) when is_map(attrs) do
    username =
      attrs
      |> Map.get("username", Map.get(attrs, :username, ""))
      |> to_string()
      |> String.trim()
      |> String.downcase()

    password =
      attrs
      |> Map.get("password", Map.get(attrs, :password, ""))
      |> to_string()

    email =
      attrs
      |> Map.get("email", Map.get(attrs, :email))
      |> blank_to_nil()

    cond do
      not Regex.match?(@username, username) ->
        {:error,
         %Error{
           message: "Username must be 3–40 letters, numbers, dots, underscores, or hyphens",
           kind: :config
         }}

      byte_size(password) < 10 ->
        {:error, %Error{message: "Password must be at least 10 characters", kind: :config}}

      is_binary(email) and not Regex.match?(@email, email) ->
        {:error, %Error{message: "Email is not valid", kind: :config}}

      true ->
        {:ok, %{username: username, password: password, email: email}}
    end
  end

  def create(attrs) when is_map(attrs) do
    with :ok <- require_repo(),
         :ok <- require_empty(),
         {:ok, attrs} <- validate_attrs(attrs) do
      ensure_table()
      hash = hash_password(attrs.password)

      verified_at =
        if attrs.email, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      %{rows: [[id]]} =
        repo().query!(
          """
          INSERT INTO phoenix_lens_operators (username, password_hash, email, email_verified_at, inserted_at, updated_at)
          VALUES ($1, $2, $3, $4, NOW(), NOW())
          RETURNING id
          """,
          [attrs.username, hash, attrs.email, verified_at],
          log: false
        )

      {:ok, %{id: id, username: attrs.username, email: attrs.email}}
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def authenticate(username, password) do
    with :ok <- require_repo() do
      username = username |> to_string() |> String.trim() |> String.downcase()
      password = to_string(password)
      ensure_table()

      case query_maps(
             """
             SELECT id, username, password_hash, email, email_verified_at
             FROM phoenix_lens_operators
             WHERE username = $1
             LIMIT 1
             """,
             [username]
           ) do
        [row] ->
          if verify_password(password, row["password_hash"]) do
            {:ok, row}
          else
            {:error, %Error{message: "Invalid username or password", kind: :config}}
          end

        _ ->
          _ = dummy_verify()
          {:error, %Error{message: "Invalid username or password", kind: :config}}
      end
    end
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def hash_password(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(16)
    digest = :crypto.pbkdf2_hmac(:sha256, password, salt, @iterations, @digest_size)

    Enum.join(
      [
        "pbkdf2_sha256",
        Integer.to_string(@iterations),
        Base.encode64(salt, padding: false),
        Base.encode64(digest, padding: false)
      ],
      "$"
    )
  end

  def verify_password(password, hash) when is_binary(password) and is_binary(hash) do
    case String.split(hash, "$") do
      ["pbkdf2_sha256", iterations, salt_b64, digest_b64] ->
        iterations = String.to_integer(iterations)
        salt = Base.decode64!(salt_b64, padding: false)
        expected = Base.decode64!(digest_b64, padding: false)
        actual = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, byte_size(expected))
        Plug.Crypto.secure_compare(actual, expected)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def verify_password(_, _), do: false

  def issue_email_code(email) when is_binary(email) do
    email = String.downcase(String.trim(email))
    code = email_code()
    now = System.system_time(:second)
    :ets.insert(codes_table(), {email, %{code: code, at: now, tries: 0}})
    {:ok, code}
  end

  def verify_email_code(email, code) when is_binary(email) and is_binary(code) do
    email = String.downcase(String.trim(email))
    code = String.replace(code, ~r/\s+/, "")
    now = System.system_time(:second)

    case :ets.lookup(codes_table(), email) do
      [{^email, %{code: expected, at: at, tries: tries}}]
      when now - at < @code_ttl and tries < 10 ->
        if Plug.Crypto.secure_compare(expected, code) do
          :ets.delete(codes_table(), email)
          true
        else
          :ets.insert(codes_table(), {email, %{code: expected, at: at, tries: tries + 1}})
          false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def verify_email_code(_, _), do: false

  def issue_session_ticket(%{id: id, username: username}) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    :ets.insert(
      tickets_table(),
      {token, %{at: System.system_time(:second), id: id, username: username}}
    )

    token
  end

  def consume_session_ticket(token) when is_binary(token) do
    now = System.system_time(:second)

    case :ets.take(tickets_table(), token) do
      [{^token, %{at: at} = meta}] when now - at < @ticket_ttl -> {:ok, meta}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  def consume_session_ticket(_), do: :error

  def send_code(email, purpose) when is_binary(email) do
    cond do
      not smtp_configured?() ->
        {:error, %Error{message: "SMTP is not configured", kind: :config}}

      not Mailer.available?() ->
        {:error, %Error{message: Mailer.missing_message(), kind: :config}}

      true ->
        smtp = Integrations.email()
        cfg = (smtp && (smtp["config"] || smtp[:config])) || smtp

        with {:ok, code} <- issue_email_code(email) do
          case Mailer.send(cfg, email, subject(purpose), body(purpose, code)) do
            :ok -> :ok
            {:error, reason} -> {:error, %Error{message: to_string(reason), kind: :config}}
          end
        end
    end
  end

  defp subject(:setup), do: "Verify your Lens email"
  defp subject(:login), do: "Your Lens sign-in code"
  defp subject(_), do: "Your Lens verification code"

  defp body(purpose, code) do
    intro =
      case purpose do
        :setup -> "Use this code to verify the operator email for Lens."
        :login -> "Use this code to finish signing in to Lens."
        _ -> "Use this code to verify your email for Lens."
      end

    """
    #{intro}

    #{code}

    It expires in 10 minutes. If you did not request this, ignore the message.
    """
  end

  defp require_repo do
    if repo() do
      :ok
    else
      {:error, %Error{message: "PhoenixLens metadata repo is not configured", kind: :config}}
    end
  end

  defp require_empty do
    if configured?() do
      {:error, %Error{message: "Lens already has an operator. Sign in instead.", kind: :config}}
    else
      :ok
    end
  end

  defp dummy_verify do
    verify_password("dummy-password", hash_password("dummy-password"))
  end

  defp email_code do
    n = :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned() |> rem(1_000_000)
    n |> Integer.to_string() |> String.pad_leading(6, "0")
  end

  defp codes_table, do: named_table(@codes)
  defp tickets_table, do: named_table(@tickets)

  defp named_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:named_table, :public, :set, read_concurrency: true])
      tid -> tid
    end
  rescue
    ArgumentError -> name
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
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value) |> String.downcase()
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(_), do: nil
end
