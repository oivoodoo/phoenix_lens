defmodule PhoenixLens.Standalone.SessionController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  def complete(conn, %{"t" => ticket}) do
    prefix = conn.assigns[:lens_prefix] || "/lens"

    case PhoenixLens.Operator.consume_session_ticket(ticket) do
      {:ok, meta} ->
        conn
        |> put_session(:lens_operator_id, meta.id)
        |> put_session(:lens_operator, meta.username)
        |> put_session(:lens_unlocked, true)
        |> redirect(to: prefix)

      :error ->
        redirect(conn, to: prefix <> "/login")
    end
  end

  def complete(conn, _params) do
    prefix = conn.assigns[:lens_prefix] || "/lens"
    redirect(conn, to: prefix <> "/login")
  end

  def delete(conn, _params) do
    prefix = conn.assigns[:lens_prefix] || "/lens"

    conn
    |> configure_session(drop: true)
    |> redirect(to: prefix <> "/login")
  end
end
