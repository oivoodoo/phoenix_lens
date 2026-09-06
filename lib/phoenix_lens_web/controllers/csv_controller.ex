defmodule PhoenixLensWeb.CSVController do
  use PhoenixLensWeb, :controller

  alias PhoenixLens.{Export, Questions, Query}

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
            body = Export.csv(result)

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
end
