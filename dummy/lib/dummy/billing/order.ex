defmodule Dummy.Billing.Order do
  use Ecto.Schema

  schema "orders" do
    field :total_cents, :integer
    field :status, :string
    belongs_to :user, Dummy.Accounts.User
    timestamps(type: :utc_datetime)
  end
end
