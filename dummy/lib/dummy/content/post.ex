defmodule Dummy.Content.Post do
  use Ecto.Schema

  schema "posts" do
    field :title, :string
    field :body, :string
    field :status, :string
    field :category, :string
    field :published_at, :utc_datetime
    belongs_to :user, Dummy.Accounts.User
    has_many :comments, Dummy.Content.Comment
    timestamps(type: :utc_datetime)
  end
end
