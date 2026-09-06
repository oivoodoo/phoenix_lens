defmodule PhoenixLensWeb.ResultPreview do
  @moduledoc false
  use Phoenix.LiveComponent

  alias PhoenixLens.{Export, Viz}
  alias PhoenixLensWeb.Components.ResultTable

  @viz [
    {"table", "Table"},
    {"number", "Number"},
    {"bar", "Bar"},
    {"line", "Line"},
    {"pie", "Pie"},
    {"combo", "Combo"}
  ]

  def update(assigns, socket) do
    result = assigns.result
    result_ref = result && {result.columns, result.num_rows, result.duration_ms}
    reset? = socket.assigns[:result_ref] != result_ref

    socket =
      socket
      |> assign(assigns)
      |> assign(:result_ref, result_ref)
      |> assign(:viz_types, @viz)

    socket =
      if reset? and result do
        socket
        |> assign(:viz, assigns[:viz] || "table")
        |> assign(:page, 1)
        |> assign(:page_size, Viz.page_size())
        |> assign(:x, Viz.default_x(result))
        |> assign(:y, Viz.default_y(result))
      else
        assign_new(socket, :page, fn -> 1 end)
        |> assign_new(:page_size, fn -> Viz.page_size() end)
        |> assign_new(:x, fn -> result && Viz.default_x(result) end)
        |> assign_new(:y, fn -> result && Viz.default_y(result) end)
        |> assign_new(:viz, fn -> assigns[:viz] || "table" end)
      end

    {:ok, socket}
  end

  def handle_event("set_viz", %{"viz" => viz}, socket) do
    send(self(), {:preview_viz, viz})
    {:noreply, assign(socket, viz: viz, page: 1)}
  end

  def handle_event("set_axis", %{"x" => x, "y" => y}, socket) do
    {:noreply, assign(socket, x: x, y: y)}
  end

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, assign(socket, :page, String.to_integer(to))}
  end

  def handle_event("page_size", %{"size" => size}, socket) do
    {:noreply, assign(socket, page_size: String.to_integer(size), page: 1)}
  end

  def handle_event("download", %{"format" => format}, socket) do
    result = socket.assigns.result

    {body, mime, ext} =
      case format do
        "json" -> {Export.json(result), "application/json", "json"}
        _ -> {Export.csv(result), "text/csv", "csv"}
      end

    {:noreply,
     push_event(socket, "lens-download", %{
       filename: "lens-results.#{ext}",
       mime: mime,
       body: body
     })}
  end

  def render(%{result: nil} = assigns), do: ~H""

  def render(assigns) do
    page = Viz.page(assigns.result, assigns.page, assigns.page_size)
    assigns = assign(assigns, :page_info, page)

    ~H"""
    <div id={"result-preview-#{@id}"} class="lens-preview" phx-hook="ResultDownload">
      <div class="lens-preview-bar">
        <div class="lens-viz-picker" role="tablist" aria-label="Visualization">
          <button
            :for={{id, label} <- @viz_types}
            type="button"
            role="tab"
            aria-selected={@viz == id}
            class={if @viz == id, do: "active"}
            phx-click="set_viz"
            phx-value-viz={id}
            phx-target={@myself}
          >
            {label}
          </button>
        </div>
        <div class="lens-preview-actions">
          <button
            type="button"
            class="ghost"
            phx-click="download"
            phx-value-format="csv"
            phx-target={@myself}
          >
            Export CSV
          </button>
          <button
            type="button"
            class="ghost"
            phx-click="download"
            phx-value-format="json"
            phx-target={@myself}
          >
            Export JSON
          </button>
        </div>
      </div>

      <form
        :if={@viz != "table"}
        class="lens-axis-row"
        phx-change="set_axis"
        phx-target={@myself}
      >
        <label class="lens-chip">
          X axis
          <select name="x">
            <option :for={col <- @result.columns} value={col} selected={col == @x}>{col}</option>
          </select>
        </label>
        <label class="lens-chip">
          Y axis
          <select name="y">
            <option value="__count__" selected={@y == "__count__"}>Count of rows</option>
            <option :for={col <- @result.columns} value={col} selected={col == @y}>{col}</option>
          </select>
        </label>
      </form>

      <div class="lens-preview-body">
        <ResultTable.visualization result={@result} viz={@viz} x={@x} y={@y} page_info={@page_info} />
      </div>

      <div :if={@viz == "table"} class="lens-pager">
        <span class="lens-muted">
          Showing {@page_info.from}–{@page_info.to} of {@page_info.total}
        </span>
        <div class="lens-pager-btns">
          <button
            type="button"
            class="ghost"
            disabled={@page_info.page <= 1}
            phx-click="page"
            phx-value-to={@page_info.page - 1}
            phx-target={@myself}
          >
            Prev
          </button>
          <button
            type="button"
            class="ghost"
            disabled={@page_info.page >= @page_info.pages}
            phx-click="page"
            phx-value-to={@page_info.page + 1}
            phx-target={@myself}
          >
            Next
          </button>
        </div>
        <form class="lens-chip" phx-change="page_size" phx-target={@myself}>
          Rows
          <select name="size">
            <option value="10" selected={@page_size == 10}>10</option>
            <option value="25" selected={@page_size == 25}>25</option>
            <option value="50" selected={@page_size == 50}>50</option>
            <option value="100" selected={@page_size == 100}>100</option>
          </select>
        </form>
      </div>
    </div>
    """
  end
end
