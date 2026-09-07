defmodule PhoenixLens.AuthTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Auth

  test "otpauth_uri names the Lens issuer" do
    uri = Auth.otpauth_uri("MFRGGZDFMZTWQ2LK")
    assert uri =~ "otpauth://totp/"
    assert uri =~ "issuer=Lens"
  end

  test "qr_svg renders an svg" do
    svg = Auth.qr_svg("MFRGGZDFMZTWQ2LK")
    assert svg =~ "<svg"
  end

  test "rp_id is the origin host" do
    assert Auth.rp_id("http://localhost:4000") == "localhost"
    assert Auth.rp_id("https://lens.example.com") == "lens.example.com"
  end

  test "origin_from keeps scheme, host, and non-default port" do
    assert Auth.origin_from("http://localhost:4000/lens", "http://fallback") ==
             "http://localhost:4000"

    assert Auth.origin_from("https://lens.example.com", "http://fallback") ==
             "https://lens.example.com"

    assert Auth.origin_from("javascript:alert(1)", "http://localhost:4000") ==
             "http://localhost:4000"
  end

  test "challenge_bytes encodes the wax challenge" do
    challenge = Auth.registration_challenge("http://localhost:4000")
    bytes = Auth.challenge_bytes(challenge)
    assert is_binary(bytes)
    assert byte_size(Base.decode64!(bytes)) == byte_size(challenge.bytes)
  end

  test "required? is false when nothing is enrolled" do
    refute Auth.required?()
  end

  test "verify_totp is false without an enabled secret" do
    refute Auth.verify_totp("123456")
  end

  test "start_totp needs a metadata repo" do
    assert {:error, %{kind: :config}} = Auth.start_totp()
  end

  test "register_passkey rejects a bogus attestation" do
    challenge = Auth.registration_challenge("http://localhost:4000")

    assert {:error, %{kind: :config}} =
             Auth.register_passkey("laptop", %{"attestationObject" => "nope"}, challenge)
  end

  test "unlock ticket is single-use" do
    token = Auth.issue_unlock_ticket(to: "/lens/settings/security", flash: "ok")
    assert {:ok, meta} = Auth.consume_unlock_ticket(token)
    assert meta.to == "/lens/settings/security"
    assert meta.flash == "ok"
    assert :error = Auth.consume_unlock_ticket(token)
    assert :error = Auth.consume_unlock_ticket("nope")
  end

  test "NimbleTOTP codes match the stored base32 secret" do
    secret = NimbleTOTP.secret()
    encoded = Base.encode32(secret, padding: false)
    code = NimbleTOTP.verification_code(secret)
    {:ok, decoded} = Base.decode32(encoded, padding: false)
    assert NimbleTOTP.valid?(decoded, code)
    refute NimbleTOTP.valid?(decoded, "000000")
  end
end
