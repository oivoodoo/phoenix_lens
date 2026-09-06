defmodule PhoenixLensWeb.Components.ResultTable do
  @moduledoc false
  use Phoenix.Component

  alias PhoenixLens.Result

  @palette ["#509EE3", "#88BF4D", "#A989C5", "#F9D45C", "#EF8C8C", "#F2A86F", "#98D9D9"]

  attr :result, :map, required: true

  def result_table(%{result: nil} = assigns), do: ~H""

  def result_table(assigns) do
    ~H"""
    <div class="lens-table-wrap">
      <table class="lens-table">
        <thead>
          <tr>
            <th :for={col <- @result.columns} class={masked_class(@result, col)}>{col}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @result.rows}>
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
        Showing {min(@result.num_rows, length(@result.rows))}
        {if @result.num_rows == 1, do: "row", else: "rows"} · {@result.duration_ms} ms
        <%= if @result.truncated do %>
          · truncated
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

  def visualization(assigns) do
    ~H"""
    <%= case @viz do %>
      <% "number" -> %>
        <.kpi result={@result} />
      <% "bar" -> %>
        <.column_chart result={@result} />
      <% "line" -> %>
        <.column_chart result={@result} line={true} />
      <% "combo" -> %>
        <.column_chart result={@result} line={true} />
      <% "pie" -> %>
        <.pie result={@result} />
      <% _ -> %>
        <.result_table result={@result} />
    <% end %>
    """
  end

  attr :result, :map, required: true

  def kpi(assigns) do
    {value, hint} = kpi_bits(assigns.result)
    assigns = assign(assigns, value: value, hint: hint)

    ~H"""
    <div class="lens-kpi-block">
      <div class="lens-kpi">{@value}</div>
      <p :if={@hint} class="lens-muted">{@hint}</p>
    </div>
    """
  end

  attr :result, :map, required: true
  attr :line, :boolean, default: false

  def column_chart(assigns) do
    pairs = chart_pairs(assigns.result)
    max_v = pairs |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) |> max(1)
    w = 640
    h = 220
    n = max(length(pairs), 1)
    gap = 12
    bar_w = max(trunc((w - 40) / n - gap), 8)

    points =
      pairs
      |> Enum.with_index()
      |> Enum.map(fn {{_label, value}, i} ->
        x = 28 + i * (bar_w + gap) + bar_w / 2
        y = 12 + (1 - value / max_v) * 170
        {x, y}
      end)

    polyline =
      Enum.map_join(points, " ", fn {x, y} -> "#{x},#{y}" end)

    assigns =
      assign(assigns,
        pairs: pairs,
        max_v: max_v,
        w: w,
        h: h,
        bar_w: bar_w,
        gap: gap,
        polyline: polyline
      )

    ~H"""
    <%= if @pairs == [] do %>
      <.result_table result={@result} />
    <% else %>
      <svg class="lens-chart" viewBox={"0 0 #{@w} #{@h}"} role="img">
        <%= for {{label, value}, i} <- Enum.with_index(@pairs) do %>
          <rect
            x={28 + i * (@bar_w + @gap)}
            y={12 + (1 - value / @max_v) * 170}
            width={@bar_w}
            height={max(value / @max_v * 170, 1)}
            rx="3"
            class="lens-chart-bar"
          />
          <text
            x={28 + i * (@bar_w + @gap) + @bar_w / 2}
            y="210"
            text-anchor="middle"
            class="lens-chart-label"
          >
            {short(label)}
          </text>
        <% end %>
        <polyline :if={@line} points={@polyline} class="lens-chart-line" fill="none" />
      </svg>
    <% end %>
    """
  end

  attr :result, :map, required: true

  def pie(assigns) do
    pairs = chart_pairs(assigns.result)
    total = pairs |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> max(1)
    slices = pie_slices(pairs, total)
    assigns = assign(assigns, pairs: pairs, total: total, slices: slices)

    ~H"""
    <%= if @pairs == [] do %>
      <.result_table result={@result} />
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

  defp kpi_bits(%{rows: [[v | _] | rest]} = result) do
    hint =
      cond do
        result.masked_columns != [] ->
          "Masked: #{Enum.join(result.masked_columns, ", ")}"

        match?([[_prev | _] | _], rest) ->
          "First of #{result.num_rows} rows"

        true ->
          nil
      end

    {Result.display_cell(v), hint}
  end

  defp kpi_bits(_), do: {"—", nil}

  defp masked_class(result, col) do
    if col in result.masked_columns, do: "masked", else: ""
  end

  defp chart_pairs(%{columns: cols, rows: rows}) when length(cols) >= 2 do
    rows
    |> Enum.take(16)
    |> Enum.map(fn row ->
      label = Result.display_cell(Enum.at(row, 0))
      num = to_number(Enum.at(row, -1)) || to_number(Enum.at(row, 1))
      {label, num}
    end)
    |> Enum.reject(fn {_l, n} -> is_nil(n) end)
  end

  defp chart_pairs(_), do: []

  defp to_number(n) when is_number(n), do: n * 1.0
  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(:redacted), do: nil
  defp to_number(_), do: nil

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
