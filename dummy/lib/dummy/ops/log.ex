defmodule Dummy.Ops.Log do
  use Ecto.Schema

  schema "logs" do
    field :event, :string
    field :path, :string
    field :ip, :string, redact: true
    field :user_agent, :string
    field :status_code, :integer
    belongs_to :user, Dummy.Accounts.User
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
