defmodule PhoenixLensWeb.Components.SqlEditor do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :name, :string, default: "sql"
  attr :value, :string, default: ""
  attr :rows, :integer, default: 10
  attr :catalog, :map, required: true

  def editor(assigns) do
    assigns = assign(assigns, :catalog_json, Jason.encode!(assigns.catalog))

    ~H"""
    <div class="lens-sql" id={@id <> "-wrap"} phx-update="ignore">
      <textarea
        id={@id}
        name={@name}
        rows={@rows}
        spellcheck="false"
        phx-hook="SqlEditor"
        data-catalog={@catalog_json}
        autocomplete="off"
        autocapitalize="off"
      >{@value}</textarea>
    </div>
    """
  end
end
