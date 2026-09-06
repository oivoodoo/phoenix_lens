defmodule Dummy.Billing.Subscription do
  use Ecto.Schema

  schema "subscriptions" do
    field :plan, :string
    field :status, :string
    field :amount_cents, :integer
    field :email, :string, redact: true
    field :started_at, :utc_datetime
    field :canceled_at, :utc_datetime
    belongs_to :user, Dummy.Accounts.User
    timestamps(type: :utc_datetime)
  end
end
