defmodule Dummy.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string, redact: true
    field :first_name, :string
    field :last_name, :string
    field :phone, :string
    has_many :orders, Dummy.Billing.Order
    has_many :posts, Dummy.Content.Post
    has_many :comments, Dummy.Content.Comment
    has_many :logs, Dummy.Ops.Log
    has_one :subscription, Dummy.Billing.Subscription
    timestamps(type: :utc_datetime)
  end
end
