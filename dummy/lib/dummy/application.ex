defmodule Dummy.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Dummy.Repo,
      {Phoenix.PubSub, name: Dummy.PubSub},
      DummyWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Dummy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DummyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
