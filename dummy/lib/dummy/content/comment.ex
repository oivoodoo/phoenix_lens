defmodule Dummy.Content.Comment do
  use Ecto.Schema

  schema "comments" do
    field :body, :string
    field :author_email, :string, redact: true
    belongs_to :post, Dummy.Content.Post
    belongs_to :user, Dummy.Accounts.User
    timestamps(type: :utc_datetime)
  end
end
