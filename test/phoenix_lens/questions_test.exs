defmodule PhoenixLens.QuestionsTest do
  use ExUnit.Case, async: false

  alias PhoenixLens.Questions

  defmodule FakeRepo do
    def query!(sql, params, _opts \\ []) do
      send(self(), {:query, sql, params})

      if String.contains?(sql, "INSERT") do
        Process.put(:saved_sql, Enum.at(params, 1))
        %{rows: [[1]], columns: ["id"]}
      else
        %{
          rows: [
            [
              1,
              "Recent",
              Process.get(:saved_sql),
              "table",
              "primary",
              nil,
              nil
            ]
          ],
          columns: ["id", "name", "sql", "viz", "database_id", "inserted_at", "updated_at"]
        }
      end
    end
  end

  setup do
    previous = Application.get_all_env(:phoenix_lens)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_lens),
          do: Application.delete_env(:phoenix_lens, key)

      for {key, value} <- previous, do: Application.put_env(:phoenix_lens, key, value)
    end)

    Application.delete_env(:phoenix_lens, :databases)
    Application.put_env(:phoenix_lens, :repo, FakeRepo)
    :ok
  end

  test "save keeps email literals in the question SQL" do
    sql = "SELECT id FROM users WHERE email = 'alice@example.com'"

    assert {:ok, question} = Questions.save(%{"name" => "Recent", "sql" => sql})

    assert_received {:query, insert, params}
    assert insert =~ "INSERT INTO phoenix_lens_questions"
    assert sql in params
    refute Enum.any?(params, &(is_binary(&1) and String.contains?(&1, "[redacted]")))
    assert question["sql"] == sql
    assert question["sql"] =~ "alice@example.com"
  end
end
