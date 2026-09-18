defmodule PhoenixLens.Standalone.Repo do
  @moduledoc false
  use Ecto.Repo, otp_app: :phoenix_lens, adapter: Ecto.Adapters.Postgres
end
