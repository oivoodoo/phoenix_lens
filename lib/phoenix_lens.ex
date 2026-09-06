defmodule PhoenixLens do
  @moduledoc """
  Mountable SQL notebook for Phoenix.

  Point it at your Ecto repo, save questions, pin dashboards, and mask PII/PHI
  in every result sink.

      config :phoenix_lens,
        repo: MyApp.Repo,
        masked_fields: [:email, :first_name, :phone]

      import PhoenixLensWeb.Router

      scope "/" do
        pipe_through [:browser, :require_admin]
        lens "/lens"
      end
  """

  alias PhoenixLens.{Config, Query}

  defdelegate run(sql, opts \\ []), to: Query
  defdelegate config(), to: Config, as: :get

  def databases do
    Config.get().databases
  end
end
