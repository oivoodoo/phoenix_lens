defmodule PhoenixLensWeb.CSVController do
  use PhoenixLensWeb, :controller

  alias PhoenixLens.{Questions, Query, Result}

  def show(conn, %{"id" => id}) do
    actor = conn.assigns[:lens_actor]

    case Questions.get(id) do
      {:ok, question} ->
        case Query.run(question["sql"],
               database: question["database_id"],
               actor: actor,
               question_id: question["id"]
             ) do
          {:ok, result} ->
            body = to_csv(result)

            conn
            |> put_resp_content_type("text/csv")
            |> put_resp_header(
              "content-disposition",
              ~s(attachment; filename="question-#{question["id"]}.csv")
            )
            |> send_resp(200, body)

          {:error, error} ->
            send_resp(conn, 400, error.message)
        end

      {:error, error} ->
        send_resp(conn, 404, error.message)
    end
  end

  defp to_csv(result) do
    header = Enum.map_join(result.columns, ",", &escape/1)

    rows =
      Enum.map_join(result.rows, "\n", fn row ->
        Enum.map_join(row, ",", fn cell -> escape(Result.display_cell(cell)) end)
      end)

    header <> "\n" <> rows <> "\n"
  end

  defp escape(value) do
    value = to_string(value)

    if String.contains?(value, [",", "\"", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end
end
