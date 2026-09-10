# `PhoenixLens.Auth`
[🔗](https://github.com/oivoodoo/phoenix_lens/blob/v0.1.5/lib/phoenix_lens/auth.ex#L1)

Optional Lens lock: authenticator-app TOTP and WebAuthn passkeys.

When either is enabled, the UI asks for a second factor at `/unlock`.
MCP tokens are unaffected. Disable everything from IEx with `reset!/0`
if you lock yourself out.

# `auth_sql`

# `authenticate_passkey`

# `authentication_challenge`

# `cancel_totp_setup`

# `challenge_bytes`

# `confirm_totp`

# `consume_unlock_ticket`

# `disable_totp`

# `ensure_tables`

# `issue_unlock_ticket`

# `origin_from`

WebAuthn origin from the browser (`window.location.origin`), falling back
to the endpoint URL. Must match the page origin exactly, including port.

# `otpauth_uri`

# `passkeys`

# `passkeys_sql`

# `qr_svg`

# `register_passkey`

# `registration_challenge`

# `required?`

# `reset!`

# `revoke_passkey`

# `rp_id`

# `start_totp`

# `totp_enabled?`

# `totp_pending?`

# `verify_totp`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
