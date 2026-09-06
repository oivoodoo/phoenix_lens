defmodule PhoenixLens.Dashboards do
  @moduledoc """
  Dashboards of saved questions.
  """

  alias PhoenixLens.{Config, Error}

  def list do
    query_maps("""
    SELECT id, name, inserted_at, updated_at
    FROM phoenix_lens_dashboards
    ORDER BY updated_at DESC
    """)
  end

  def get(id) do
    case query_maps(
           "SELECT id, name, inserted_at, updated_at FROM phoenix_lens_dashboards WHERE id = $1",
           [to_int(id)]
         ) do
      [dash] ->
        cards =
          query_maps(
            """
            SELECT c.id, c.dashboard_id, c.question_id, c.position, c.date_column,
                   q.name AS question_name, q.sql, q.viz, q.database_id
            FROM phoenix_lens_dashboard_cards c
            JOIN phoenix_lens_questions q ON q.id = c.question_id
            WHERE c.dashboard_id = $1
            ORDER BY c.position ASC, c.id ASC
            """,
            [to_int(id)]
          )

        {:ok, Map.put(dash, "cards", cards)}

      [] ->
        {:error, %Error{message: "dashboard not found", kind: :sql}}
    end
  end

  def save(attrs) when is_map(attrs) do
    name = attrs[:name] || attrs["name"] || "Untitled"
    id = attrs[:id] || attrs["id"]
    repo = metadata_repo!()

    cond do
      is_nil(repo) ->
        {:error, %Error{message: "no metadata repo configured", kind: :config}}

      id ->
        repo.query!(
          "UPDATE phoenix_lens_dashboards SET name = $2, updated_at = NOW() WHERE id = $1",
          [to_int(id), name],
          log: false
        )

        get(id)

      true ->
        %{rows: [[new_id]]} =
          repo.query!(
            """
            INSERT INTO phoenix_lens_dashboards (name, inserted_at, updated_at)
            VALUES ($1, NOW(), NOW())
            RETURNING id
            """,
            [name],
            log: false
          )

        get(new_id)
    end
  end

  def add_card(dashboard_id, question_id, opts \\ []) do
    repo = metadata_repo!()
    date_column = opts[:date_column] || opts["date_column"]

    %{rows: [[pos]]} =
      repo.query!(
        "SELECT COALESCE(MAX(position), -1) + 1 FROM phoenix_lens_dashboard_cards WHERE dashboard_id = $1",
        [to_int(dashboard_id)],
        log: false
      )

    repo.query!(
      """
      INSERT INTO phoenix_lens_dashboard_cards
        (dashboard_id, question_id, position, date_column, inserted_at)
      VALUES ($1, $2, $3, $4, NOW())
      """,
      [to_int(dashboard_id), to_int(question_id), pos, date_column],
      log: false
    )

    get(dashboard_id)
  end

  def remove_card(card_id) do
    metadata_repo!().query!(
      "DELETE FROM phoenix_lens_dashboard_cards WHERE id = $1",
      [to_int(card_id)],
      log: false
    )

    :ok
  end

  def delete(id) do
    metadata_repo!().query!(
      "DELETE FROM phoenix_lens_dashboards WHERE id = $1",
      [to_int(id)],
      log: false
    )

    :ok
  end

  def wrap_date_filter(sql, date_column, from, to)
      when is_binary(date_column) and date_column != "" do
    ident = quote_ident(date_column)
    from = from || "1900-01-01"
    to = to || "9999-12-31"

    """
    SELECT * FROM (
    #{sql}
    ) AS phoenix_lens_q
    WHERE phoenix_lens_q.#{ident} >= DATE '#{escape_date(from)}'
      AND phoenix_lens_q.#{ident} < DATE '#{escape_date(to)}'
    """
  end

  def wrap_date_filter(sql, _, _, _), do: sql

  defp quote_ident(name) do
    if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, name) do
      name
    else
      "\"" <> String.replace(name, "\"", "\"\"") <> "\""
    end
  end

  defp escape_date(value) do
    value
    |> to_string()
    |> String.replace(~r/[^0-9T:Z.\-]/, "")
    |> String.slice(0, 32)
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

  defp metadata_repo!, do: Config.get().metadata_repo
  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)
end
