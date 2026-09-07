defmodule PhoenixLensWeb.Components.SettingsNav do
  @moduledoc false
  use Phoenix.Component

  attr :lens_prefix, :string, required: true
  attr :section, :atom, required: true

  def bar(assigns) do
    ~H"""
    <nav class="lens-settings-nav" aria-label="Settings sections">
      <a
        href={"#{@lens_prefix}/settings"}
        class={if @section == :engine, do: "active"}
      >
        Engine & sources
      </a>
      <a
        href={"#{@lens_prefix}/settings/protection"}
        class={if @section == :protection, do: "active"}
      >
        Column protection
      </a>
    </nav>
    """
  end
end
