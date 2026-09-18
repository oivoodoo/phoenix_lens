defmodule PhoenixLens.OperatorTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.{Error, Operator}

  test "hashes and verifies a password" do
    hash = Operator.hash_password("correct horse battery")
    assert hash =~ "pbkdf2_sha256$"
    assert Operator.verify_password("correct horse battery", hash)
    refute Operator.verify_password("wrong password", hash)
    refute Operator.verify_password("correct horse battery", "not-a-hash")
  end

  test "validates username, password, and email" do
    assert {:error, %Error{message: message}} = Operator.validate_attrs(%{"username" => "ab"})
    assert message =~ "Username"

    assert {:error, %Error{message: message}} =
             Operator.validate_attrs(%{"username" => "ops", "password" => "short"})

    assert message =~ "Password"

    assert {:ok, attrs} =
             Operator.validate_attrs(%{
               "username" => "Ops-User",
               "password" => "long-enough-secret"
             })

    assert attrs.username == "ops-user"
    assert attrs.password == "long-enough-secret"
    assert attrs.email == nil

    assert {:ok, %{email: "ops@example.com"}} =
             Operator.validate_attrs(%{
               "username" => "ops",
               "password" => "long-enough-secret",
               "email" => "ops@example.com"
             })

    assert {:error, %Error{message: message}} =
             Operator.validate_attrs(%{
               "username" => "ops",
               "password" => "long-enough-secret",
               "email" => "not-an-email"
             })

    assert message =~ "Email"
  end

  test "email codes are single-use and expire from the table" do
    assert {:ok, code} = Operator.issue_email_code("ops@example.com")
    assert code =~ ~r/^\d{6}$/
    assert Operator.verify_email_code("ops@example.com", code)
    refute Operator.verify_email_code("ops@example.com", code)
    refute Operator.verify_email_code("ops@example.com", "000000")
  end

  test "session tickets are single-use" do
    token = Operator.issue_session_ticket(%{id: 7, username: "ops"})
    assert {:ok, meta} = Operator.consume_session_ticket(token)
    assert meta.id == 7
    assert meta.username == "ops"
    assert :error = Operator.consume_session_ticket(token)
    assert :error = Operator.consume_session_ticket("nope")
  end

  test "smtp_configured? is true when env SMTP is set" do
    previous = Application.get_env(:phoenix_lens, :smtp)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:phoenix_lens, :smtp, previous),
        else: Application.delete_env(:phoenix_lens, :smtp)
    end)

    Application.delete_env(:phoenix_lens, :smtp)
    refute Operator.smtp_configured?()

    Application.put_env(:phoenix_lens, :smtp,
      host: "smtp.example.com",
      from: "lens@example.com"
    )

    assert Operator.smtp_configured?()
  end

  test "configured? is false without a metadata repo" do
    refute Operator.configured?()
  end

  test "authenticate returns error without a metadata repo" do
    assert {:error, %Error{kind: :config}} = Operator.authenticate("ops", "secret")
  end
end

defmodule PhoenixLens.OperatorIntegrationTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.{Operator, Standalone}

  @moduletag :integration

  setup do
    url = System.get_env("DATABASE_URL")
    previous = Application.get_all_env(:phoenix_lens)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_lens),
          do: Application.delete_env(:phoenix_lens, key)

      for {key, value} <- previous, do: Application.put_env(:phoenix_lens, key, value)
    end)

    Application.put_env(:phoenix_lens, :repo, PhoenixLens.Standalone.Repo)

    Application.put_env(:phoenix_lens, PhoenixLens.Standalone.Repo,
      url: url,
      pool_size: 2
    )

    start_supervised!(PhoenixLens.Standalone.Repo)
    PhoenixLens.Migrations.ensure_all(PhoenixLens.Standalone.Repo)
    PhoenixLens.Standalone.Repo.query!("DELETE FROM phoenix_lens_operators", [])
    :ok
  end

  test "create then authenticate the operator" do
    refute Operator.configured?()

    assert {:ok, operator} =
             Operator.create(%{
               "username" => "ops",
               "password" => "long-enough-secret",
               "email" => "ops@example.com"
             })

    assert operator.username == "ops"
    assert Operator.configured?()

    assert {:ok, row} = Operator.authenticate("ops", "long-enough-secret")
    assert row["username"] == "ops"
    assert row["email"] == "ops@example.com"
    assert {:error, %{message: message}} = Operator.authenticate("ops", "wrong-password-xx")
    assert message =~ "Invalid"

    assert {:error, %{message: message}} =
             Operator.create(%{"username" => "other", "password" => "long-enough-secret"})

    assert message =~ "already"
  end

  test "database_url from POSTGRES_* is accepted by configure!" do
    url = System.get_env("DATABASE_URL")
    uri = URI.parse(url)
    {user, password} = userinfo(uri)
    System.put_env("POSTGRES_HOST", uri.host)
    System.put_env("POSTGRES_PORT", Integer.to_string(uri.port || 5432))
    System.put_env("POSTGRES_USER", user)
    System.put_env("POSTGRES_PASSWORD", password || "")
    System.put_env("POSTGRES_DB", String.trim_leading(uri.path || "/postgres", "/"))
    System.delete_env("DATABASE_URL")

    on_exit(fn ->
      if url, do: System.put_env("DATABASE_URL", url)
      System.delete_env("POSTGRES_HOST")
      System.delete_env("POSTGRES_PORT")
      System.delete_env("POSTGRES_USER")
      System.delete_env("POSTGRES_PASSWORD")
      System.delete_env("POSTGRES_DB")
    end)

    assert is_binary(Standalone.database_url())
    assert Standalone.database_url() =~ uri.host
  end

  defp userinfo(%URI{userinfo: nil}), do: {"postgres", ""}

  defp userinfo(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {URI.decode(user), ""}
      [user, password] -> {URI.decode(user), URI.decode(password)}
    end
  end
end
