defmodule Dummy.Repo.Migrations.AddContentTables do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:posts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text
      add :status, :string, null: false, default: "published"
      add :category, :string
      add :published_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    alter table(:posts) do
      add_if_not_exists :status, :string, default: "published"
      add_if_not_exists :category, :string
      add_if_not_exists :published_at, :utc_datetime
    end

    create_if_not_exists index(:posts, [:user_id])
    create_if_not_exists index(:posts, [:category])
    create_if_not_exists index(:posts, [:status])

    create_if_not_exists table(:comments) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :body, :text, null: false
      add :author_email, :string
      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:comments, [:post_id])
    create_if_not_exists index(:comments, [:user_id])

    create_if_not_exists table(:logs) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :event, :string, null: false
      add :path, :string
      add :ip, :string
      add :user_agent, :string
      add :status_code, :integer
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create_if_not_exists index(:logs, [:user_id])
    create_if_not_exists index(:logs, [:event])
    create_if_not_exists index(:logs, [:inserted_at])

    create_if_not_exists table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan, :string, null: false
      add :status, :string, null: false, default: "active"
      add :amount_cents, :integer, null: false
      add :email, :string
      add :started_at, :utc_datetime
      add :canceled_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:subscriptions, [:user_id])
    create_if_not_exists index(:subscriptions, [:plan])
    create_if_not_exists index(:subscriptions, [:status])
  end
end
