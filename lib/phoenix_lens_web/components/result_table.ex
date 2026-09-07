defmodule PhoenixLensWeb.Components.ResultTable do
  @moduledoc false
  use Phoenix.Component

  alias PhoenixLens.{Result, Viz}

  @palette ["#04A9F5", "#FF9F43", "#1DE9B6", "#E83E8C", "#3F4D67", "#F4C22B", "#3EBFEA"]

  attr :result, :map, required: true
  attr :page_info, :map, default: nil

  def result_table(%{result: nil} = assigns), do: ~H""

  def result_table(assigns) do
    rows =
      case assigns[:page_info] do
        %{rows: rows} -> rows
        _ -> assigns.result.rows
      end

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div class="lens-table-wrap">
      <table class="lens-table">
        <thead>
          <tr>
            <th :for={col <- @result.columns} class={masked_class(@result, col)}>{col}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows}>
            <td
              :for={{col, value} <- Enum.zip(@result.columns, row)}
              class={masked_class(@result, col)}
            >
              {Result.display_cell(value)}
            </td>
          </tr>
        </tbody>
      </table>
      <p class="lens-muted">
        {@result.duration_ms} ms
        <%= if @result.truncated do %>
          · truncated at query cap
        <% end %>
        <%= if @result.masked_columns != [] do %>
          · masked: {Enum.join(@result.masked_columns, ", ")}
        <% end %>
      </p>
    </div>
    """
  end

  attr :result, :map, required: true
  attr :viz, :string, default: "table"
  attr :x, :string, default: nil
  attr :y, :string, default: nil
  attr :page_info, :map, default: nil

  def visualization(assigns) do
    viz = assigns[:viz] || "table"
    {x, y} = Viz.coerce_axes(assigns.result, assigns[:x], assigns[:y], viz)
    pairs = Viz.series(assigns.result, x, y)
    assigns = assign(assigns, pairs: pairs, x: x, y: y, viz: viz)

    ~H"""
    <%= case @viz do %>
      <% "number" -> %>
        <.kpi result={@result} pairs={@pairs} />
      <% "bar" -> %>
        <.column_chart result={@result} pairs={@pairs} />
      <% "line" -> %>
        <.column_chart result={@result} pairs={@pairs} line={true} />
      <% "combo" -> %>
        <.column_chart result={@result} pairs={@pairs} combo={true} />
      <% "pie" -> %>
        <.pie result={@result} pairs={@pairs} />
      <% _ -> %>
        <.result_table result={@result} page_info={@page_info} />
    <% end %>
    """
  end

  attr :result, :map, required: true
  attr :pairs, :list, default: []

  def kpi(assigns) do
    {value, hint} = kpi_bits(assigns.result, assigns[:pairs] || [])
    assigns = assign(assigns, value: value, hint: hint)

    ~H"""
    <div class="lens-kpi-block">
      <div class="lens-kpi">{@value}</div>
      <p :if={@hint} class="lens-muted">{@hint}</p>
    </div>
    """
  end

  attr :result, :map, required: true
  attr :pairs, :list, default: []
  attr :line, :boolean, default: false
  attr :combo, :boolean, default: false

  def column_chart(assigns) do
    pairs = assigns[:pairs] || []
    max_v = pairs |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) |> max(1)
    w = 720
    h = 260
    pad_l = 44
    pad_r = 16
    pad_t = 16
    pad_b = 36
    plot_w = w - pad_l - pad_r
    plot_h = h - pad_t - pad_b
    n = max(length(pairs), 1)
    gap = if n > 16, do: 4, else: 10
    bar_w = max(trunc(plot_w / n - gap), 6)
    show_line = assigns[:line] == true or assigns[:combo] == true
    show_bars = assigns[:combo] == true or not show_line

    points =
      pairs
      |> Enum.with_index()
      |> Enum.map(fn {{_label, value}, i} ->
        x = pad_l + i * (bar_w + gap) + bar_w / 2
        y = pad_t + (1 - value / max_v) * plot_h
        {x, y, value}
      end)

    polyline = Enum.map_join(points, " ", fn {x, y, _} -> "#{x},#{y}" end)

    area =
      case points do
        [] ->
          ""

        [{x0, _, _} | _] = pts ->
          {xn, _, _} = List.last(pts)
          top = Enum.map_join(pts, " ", fn {x, y, _} -> "#{x},#{y}" end)
          "M #{x0},#{pad_t + plot_h} L #{top} L #{xn},#{pad_t + plot_h} Z"
      end

    grid =
      Enum.map([0.0, 0.25, 0.5, 0.75, 1.0], fn t ->
        y = pad_t + (1 - t) * plot_h
        {y, max_v * t}
      end)

    assigns =
      assign(assigns,
        pairs: pairs,
        max_v: max_v,
        w: w,
        h: h,
        pad_l: pad_l,
        pad_t: pad_t,
        plot_h: plot_h,
        bar_w: bar_w,
        gap: gap,
        polyline: polyline,
        area: area,
        points: points,
        grid: grid,
        show_line: show_line,
        show_bars: show_bars
      )

    ~H"""
    <%= if @pairs == [] do %>
      <p class="lens-empty">No numeric values to plot. Pick Count of rows or a numeric Y column.</p>
    <% else %>
      <svg
        class="lens-chart"
        viewBox={"0 0 #{@w} #{@h}"}
        width="100%"
        height="260"
        role="img"
        aria-label="chart"
      >
        <line
          :for={{y, _v} <- @grid}
          x1={@pad_l}
          y1={y}
          x2={@w - 16}
          y2={y}
          class="lens-chart-grid"
        />
        <text
          :for={{y, v} <- @grid}
          x={@pad_l - 6}
          y={y + 3}
          text-anchor="end"
          class="lens-chart-label"
        >
          {format_num(v)}
        </text>
        <%= if @show_bars do %>
          <rect
            :for={{{_label, value}, i} <- Enum.with_index(@pairs)}
            x={@pad_l + i * (@bar_w + @gap)}
            y={@pad_t + (1 - value / @max_v) * @plot_h}
            width={@bar_w}
            height={max(value / @max_v * @plot_h, 2)}
            rx="3"
            class="lens-chart-bar"
          />
        <% end %>
        <%= if @show_line do %>
          <path d={@area} class="lens-chart-area" />
          <polyline points={@polyline} class="lens-chart-line" fill="none" />
          <circle :for={{x, y, _} <- @points} cx={x} cy={y} r="3.5" class="lens-chart-dot" />
        <% end %>
        <text
          :for={{{label, _value}, i} <- Enum.with_index(@pairs)}
          x={@pad_l + i * (@bar_w + @gap) + @bar_w / 2}
          y={@h - 12}
          text-anchor="middle"
          class="lens-chart-label"
        >
          {short(label)}
        </text>
      </svg>
    <% end %>
    """
  end

  attr :result, :map, required: true
  attr :pairs, :list, default: []

  def pie(assigns) do
    pairs = assigns[:pairs] || []
    total = pairs |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> max(1)
    slices = pie_slices(pairs, total)
    assigns = assign(assigns, pairs: pairs, total: total, slices: slices)

    ~H"""
    <%= if @pairs == [] do %>
      <p class="lens-empty">This chart needs a category on X and a number (or Count of rows) on Y.</p>
    <% else %>
      <div class="lens-pie-wrap">
        <svg class="lens-pie" viewBox="0 0 180 180" role="img">
          <circle cx="90" cy="90" r="54" class="lens-pie-hole" />
          <path :for={slice <- @slices} d={slice.d} fill={slice.color} />
          <text x="90" y="88" text-anchor="middle" class="lens-pie-total">
            {format_num(@total)}
          </text>
          <text x="90" y="106" text-anchor="middle" class="lens-pie-caption">Total</text>
        </svg>
        <ul class="lens-legend">
          <li :for={{slice, {label, value}} <- Enum.zip(@slices, @pairs)}>
            <span class="swatch" style={"background:#{slice.color}"}></span>
            {label}
            <em>{round(value / @total * 100)}%</em>
          </li>
        </ul>
      </div>
    <% end %>
    """
  end

  defp pie_slices(pairs, total) do
    {slices, _} =
      pairs
      |> Enum.with_index()
      |> Enum.map_reduce(0.0, fn {{_label, value}, i}, start ->
        frac = value / total
        stop = start + frac
        slice = %{d: arc(90, 90, 78, 40, start, stop), color: Enum.at(@palette, rem(i, 7))}
        {slice, stop}
      end)

    slices
  end

  defp arc(cx, cy, r_out, r_in, start, stop) do
    a0 = start * 2 * :math.pi() - :math.pi() / 2
    a1 = stop * 2 * :math.pi() - :math.pi() / 2
    large = if stop - start > 0.5, do: 1, else: 0
    x0 = cx + r_out * :math.cos(a0)
    y0 = cy + r_out * :math.sin(a0)
    x1 = cx + r_out * :math.cos(a1)
    y1 = cy + r_out * :math.sin(a1)
    x2 = cx + r_in * :math.cos(a1)
    y2 = cy + r_in * :math.sin(a1)
    x3 = cx + r_in * :math.cos(a0)
    y3 = cy + r_in * :math.sin(a0)

    "M #{x0} #{y0} A #{r_out} #{r_out} 0 #{large} 1 #{x1} #{y1} L #{x2} #{y2} A #{r_in} #{r_in} 0 #{large} 0 #{x3} #{y3} Z"
  end

  defp kpi_bits(_result, [{_label, value} | _]) do
    {format_num(value), nil}
  end

  defp kpi_bits(%{rows: [[v | _] | _]} = result, _) do
    hint =
      if result.masked_columns != [] do
        "Masked: #{Enum.join(result.masked_columns, ", ")}"
      end

    {Result.display_cell(v), hint}
  end

  defp kpi_bits(_, _), do: {"—", nil}

  defp masked_class(result, col) do
    if col in result.masked_columns, do: "masked", else: ""
  end

  defp short(label) when is_binary(label) and byte_size(label) > 10,
    do: String.slice(label, 0, 9) <> "…"

  defp short(label), do: label

  defp format_num(n) when is_float(n) and n == trunc(n), do: trunc(n) |> format_int()
  defp format_num(n) when is_integer(n), do: format_int(n)
  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)

  defp format_int(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
