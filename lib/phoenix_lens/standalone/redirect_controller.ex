defmodule PhoenixLens.Standalone.RedirectController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    redirect(conn, to: "/lens")
  end
end
