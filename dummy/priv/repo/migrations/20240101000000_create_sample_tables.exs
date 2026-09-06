defmodule Dummy.Repo.Migrations.CreateSampleTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :first_name, :string
      add :last_name, :string
      add :phone, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:orders) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :total_cents, :integer, null: false
      add :status, :string, null: false, default: "paid"
      timestamps(type: :utc_datetime)
    end

    create index(:orders, [:user_id])
  end
end
