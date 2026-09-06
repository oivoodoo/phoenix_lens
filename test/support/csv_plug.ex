defmodule PhoenixLens.Test.CSVPlug do
  @moduledoc false

  def init(body), do: body

  def call(conn, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "text/csv; charset=utf-8")
    |> Plug.Conn.send_resp(200, body)
  end
end
