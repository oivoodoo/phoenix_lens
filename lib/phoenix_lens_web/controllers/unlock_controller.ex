defmodule PhoenixLensWeb.UnlockController do
  @moduledoc false
  use PhoenixLensWeb, :controller

  def complete(conn, %{"t" => ticket}) do
    prefix = conn.assigns[:lens_prefix] || "/lens"

    case PhoenixLens.Auth.consume_unlock_ticket(ticket) do
      {:ok, meta} ->
        conn
        |> put_session(:lens_unlocked, true)
        |> maybe_flash(meta[:flash])
        |> redirect(to: safe_to(meta[:to], prefix))

      :error ->
        redirect(conn, to: prefix <> "/unlock")
    end
  end

  def complete(conn, _params) do
    prefix = conn.assigns[:lens_prefix] || "/lens"
    redirect(conn, to: prefix <> "/unlock")
  end

  defp maybe_flash(conn, flash) when is_binary(flash) and flash != "" do
    put_flash(conn, :info, flash)
  end

  defp maybe_flash(conn, _), do: conn

  defp safe_to(to, prefix) when is_binary(to) do
    cond do
      String.contains?(to, "://") or String.contains?(to, "..") -> prefix
      to == prefix or String.starts_with?(to, prefix <> "/") -> to
      true -> prefix
    end
  end

  defp safe_to(_, prefix), do: prefix
end
