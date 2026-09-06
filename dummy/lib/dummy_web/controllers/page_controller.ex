defmodule DummyWeb.PageController do
  use DummyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
