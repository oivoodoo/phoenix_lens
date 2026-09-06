defmodule PhoenixLensWeb.Layouts do
  @moduledoc false
  use PhoenixLensWeb, :html

  embed_templates "layouts/*"

  attr :kind, :atom, required: true
  attr :flash, :map, required: true

  def flash(assigns) do
    ~H"""
    <%= if msg = Phoenix.Flash.get(@flash, @kind) do %>
      <div class={"lens-flash lens-flash-#{@kind}"}>{msg}</div>
    <% end %>
    """
  end
end
