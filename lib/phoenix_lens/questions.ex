defmodule PhoenixLens.Questions do
  @moduledoc """
  Saved SQL questions in the host Repo.
  """

  alias PhoenixLens.{Config, Error, Redactor}

  @viz ~w(table number bar line)

  def list do
    query_maps("""
    SELECT id, name, sql, viz, database_id, inserted_at, updated_at
    FROM phoenix_lens_questions
    ORDER BY updated_at DESC
    """)
  end

  def get(id) do
    case query_maps(
           """
           SELECT id, name, sql, viz, database_id, inserted_at, updated_at
           FROM phoenix_lens_questions
           WHERE id = $1
           """,
           [to_int(id)]
         ) do
      [question] -> {:ok, question}
      [] -> {:error, %Error{message: "question not found", kind: :sql}}
    end
  end

  def save!(attrs) when is_map(attrs) do
    case save(attrs) do
      {:ok, q} -> q
      {:error, error} -> raise error
    end
  end

  def save(attrs) when is_map(attrs) do
    name = blank_to_nil(attrs[:name] || attrs["name"]) || "Untitled"
    sql = attrs[:sql] || attrs["sql"] || ""
    viz = to_string(attrs[:viz] || attrs["viz"] || "table")
    viz = if viz in @viz, do: viz, else: "table"
    database_id = to_string(attrs[:database_id] || attrs["database_id"] || "primary")
    id = attrs[:id] || attrs["id"]
    sql = Redactor.sql(sql)

    repo = metadata_repo!()

    cond do
      String.trim(sql) == "" ->
        {:error, %Error{message: "SQL is required", kind: :sql}}

      id ->
        repo.query!(
          """
          UPDATE phoenix_lens_questions
          SET name = $2, sql = $3, viz = $4, database_id = $5, updated_at = NOW()
          WHERE id = $1
          """,
          [to_int(id), name, sql, viz, database_id],
          log: false
        )

        get(id)

      true ->
        %{rows: [[new_id]]} =
          repo.query!(
            """
            INSERT INTO phoenix_lens_questions (name, sql, viz, database_id, inserted_at, updated_at)
            VALUES ($1, $2, $3, $4, NOW(), NOW())
            RETURNING id
            """,
            [name, sql, viz, database_id],
            log: false
          )

        get(new_id)
    end
  end

  def delete(id) do
    metadata_repo!().query!(
      "DELETE FROM phoenix_lens_questions WHERE id = $1",
      [to_int(id)],
      log: false
    )

    :ok
  end

  defp query_maps(sql, params \\ []) do
    case metadata_repo!() do
      nil ->
        []

      repo ->
        %{rows: rows, columns: columns} = repo.query!(sql, params, log: false)

        Enum.map(rows, fn row ->
          columns |> Enum.map(&to_string/1) |> Enum.zip(row) |> Map.new()
        end)
    end
  rescue
    _ -> []
  end

  defp metadata_repo! do
    Config.get().metadata_repo
  end

  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end
