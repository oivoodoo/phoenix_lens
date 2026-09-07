defmodule PhoenixLens.Dashboards do
  @moduledoc """
  Dashboards of saved questions.
  """

  alias PhoenixLens.{Config, Error}

  @cols 12
  @min_w 3
  @min_h 3
  @default_w 6
  @default_h 5

  def cols, do: @cols
  def min_w, do: @min_w
  def min_h, do: @min_h
  def default_w, do: @default_w
  def default_h, do: @default_h

  def layout_alter_sql do
    """
    ALTER TABLE phoenix_lens_dashboard_cards
      ADD COLUMN IF NOT EXISTS col int NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS row int NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS size_x int NOT NULL DEFAULT 6,
      ADD COLUMN IF NOT EXISTS size_y int NOT NULL DEFAULT 5
    """
  end

  def ensure_layout do
    case metadata_repo!() do
      nil ->
        :ok

      repo ->
        repo.query!(layout_alter_sql(), [], log: false)
        :ok
    end
  rescue
    _ -> :ok
  end

  def list do
    query_maps("""
    SELECT id, name, inserted_at, updated_at
    FROM phoenix_lens_dashboards
    ORDER BY updated_at DESC
    """)
  end

  def get(id) do
    ensure_layout()

    case query_maps(
           "SELECT id, name, inserted_at, updated_at FROM phoenix_lens_dashboards WHERE id = $1",
           [to_int(id)]
         ) do
      [dash] ->
        cards =
          query_maps(
            """
            SELECT c.id, c.dashboard_id, c.question_id, c.position, c.date_column,
                   c.col, c.row, c.size_x, c.size_y,
                   q.name AS question_name, q.sql, q.viz, q.database_id
            FROM phoenix_lens_dashboard_cards c
            JOIN phoenix_lens_questions q ON q.id = c.question_id
            WHERE c.dashboard_id = $1
            ORDER BY c.position ASC, c.id ASC
            """,
            [to_int(id)]
          )

        {:ok, Map.put(dash, "cards", pack(cards))}

      [] ->
        {:error, %Error{message: "dashboard not found", kind: :sql}}
    end
  end

  def save(attrs) when is_map(attrs) do
    name = attrs[:name] || attrs["name"] || "Untitled"
    id = attrs[:id] || attrs["id"]
    repo = metadata_repo!()

    cond do
      is_nil(repo) ->
        {:error, %Error{message: "no metadata repo configured", kind: :config}}

      id ->
        repo.query!(
          "UPDATE phoenix_lens_dashboards SET name = $2, updated_at = NOW() WHERE id = $1",
          [to_int(id), name],
          log: false
        )

        get(id)

      true ->
        %{rows: [[new_id]]} =
          repo.query!(
            """
            INSERT INTO phoenix_lens_dashboards (name, inserted_at, updated_at)
            VALUES ($1, NOW(), NOW())
            RETURNING id
            """,
            [name],
            log: false
          )

        get(new_id)
    end
  end

  def add_card(dashboard_id, question_id, opts \\ []) do
    ensure_layout()
    repo = metadata_repo!()
    date_column = card_date_column(opts)
    slot = next_slot(existing_cards(dashboard_id))

    %{rows: [[pos]]} =
      repo.query!(
        "SELECT COALESCE(MAX(position), -1) + 1 FROM phoenix_lens_dashboard_cards WHERE dashboard_id = $1",
        [to_int(dashboard_id)],
        log: false
      )

    repo.query!(
      """
      INSERT INTO phoenix_lens_dashboard_cards
        (dashboard_id, question_id, position, date_column, col, row, size_x, size_y, inserted_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
      """,
      [
        to_int(dashboard_id),
        to_int(question_id),
        pos,
        date_column,
        slot["col"],
        slot["row"],
        slot["size_x"],
        slot["size_y"]
      ],
      log: false
    )

    get(dashboard_id)
  end

  def save_layout(dashboard_id, items) when is_list(items) do
    ensure_layout()
    repo = metadata_repo!()
    dash_id = to_int(dashboard_id)

    Enum.each(items, fn item ->
      layout = clamp_layout(item)
      id = to_int(item["id"] || item[:id])

      repo.query!(
        """
        UPDATE phoenix_lens_dashboard_cards
        SET col = $2, row = $3, size_x = $4, size_y = $5
        WHERE id = $1 AND dashboard_id = $6
        """,
        [id, layout["col"], layout["row"], layout["size_x"], layout["size_y"], dash_id],
        log: false
      )
    end)

    get(dash_id)
  rescue
    e -> {:error, Error.from_exception(e)}
  end

  def pack(cards) when is_list(cards) do
    cards = Enum.map(cards, fn card -> Map.merge(card, clamp_layout(card)) end)

    overlapped? =
      cards
      |> Enum.with_index()
      |> Enum.any?(fn {card, i} ->
        Enum.any?(Enum.drop(cards, i + 1), &overlaps?(card, &1))
      end)

    if overlapped? do
      cards
      |> Enum.with_index()
      |> Enum.map(fn {card, i} -> Map.merge(card, slot_map(i)) end)
    else
      cards
    end
  end

  def slot_map(index, w \\ @default_w, h \\ @default_h) when is_integer(index) do
    per_row = max(div(@cols, w), 1)

    %{
      "col" => rem(index, per_row) * w,
      "row" => div(index, per_row) * h,
      "size_x" => w,
      "size_y" => h
    }
  end

  def next_slot(cards) when is_list(cards) do
    placed = pack(cards)
    w = @default_w
    h = @default_h

    Enum.find_value(0..160, fn row ->
      Enum.find_value(0..(@cols - w)//w, fn col ->
        cand = %{"col" => col, "row" => row, "size_x" => w, "size_y" => h}
        unless Enum.any?(placed, &overlaps?(&1, cand)), do: cand
      end)
    end) || slot_map(length(cards))
  end

  def overlaps?(a, b) when is_map(a) and is_map(b) do
    ac = to_i(a["col"] || a[:col])
    ar = to_i(a["row"] || a[:row])
    ax = max(to_i(a["size_x"] || a[:size_x] || @default_w), 1)
    ay = max(to_i(a["size_y"] || a[:size_y] || @default_h), 1)
    bc = to_i(b["col"] || b[:col])
    br = to_i(b["row"] || b[:row])
    bx = max(to_i(b["size_x"] || b[:size_x] || @default_w), 1)
    by = max(to_i(b["size_y"] || b[:size_y] || @default_h), 1)
    ac < bc + bx and ac + ax > bc and ar < br + by and ar + ay > br
  end

  def clamp_layout(item) when is_map(item) do
    col = max(to_i(item["col"] || item[:col]), 0)
    row = max(to_i(item["row"] || item[:row]), 0)
    sx = max(to_i(item["size_x"] || item[:size_x] || @default_w), @min_w)
    sy = max(to_i(item["size_y"] || item[:size_y] || @default_h), @min_h)
    col = min(col, @cols - @min_w)
    sx = min(max(sx, @min_w), @cols - col)
    sy = min(max(sy, @min_h), 40)

    %{"col" => col, "row" => row, "size_x" => sx, "size_y" => sy}
  end

  def remove_card(card_id) do
    metadata_repo!().query!(
      "DELETE FROM phoenix_lens_dashboard_cards WHERE id = $1",
      [to_int(card_id)],
      log: false
    )

    :ok
  end

  def delete(id) do
    metadata_repo!().query!(
      "DELETE FROM phoenix_lens_dashboards WHERE id = $1",
      [to_int(id)],
      log: false
    )

    :ok
  end

  def wrap_date_filter(sql, date_column, from, to)
      when is_binary(date_column) and date_column != "" do
    ident = quote_ident(date_column)
    from = from || "1900-01-01"
    to = to || "9999-12-31"

    """
    SELECT * FROM (
    #{sql}
    ) AS phoenix_lens_q
    WHERE phoenix_lens_q.#{ident} >= DATE '#{escape_date(from)}'
      AND phoenix_lens_q.#{ident} < DATE '#{escape_date(to)}'
    """
  end

  def wrap_date_filter(sql, _, _, _), do: sql

  defp quote_ident(name) do
    if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, name) do
      name
    else
      "\"" <> String.replace(name, "\"", "\"\"") <> "\""
    end
  end

  defp escape_date(value) do
    value
    |> to_string()
    |> String.replace(~r/[^0-9T:Z.\-]/, "")
    |> String.slice(0, 32)
  end

  defp card_date_column(opts) when is_list(opts) do
    Keyword.get(opts, :date_column)
  end

  defp card_date_column(opts) when is_map(opts) do
    opts[:date_column] || opts["date_column"]
  end

  defp card_date_column(_), do: nil

  defp existing_cards(dashboard_id) do
    query_maps(
      """
      SELECT id, col, row, size_x, size_y, position
      FROM phoenix_lens_dashboard_cards
      WHERE dashboard_id = $1
      ORDER BY position ASC, id ASC
      """,
      [to_int(dashboard_id)]
    )
  rescue
    _ -> []
  end

  defp to_i(nil), do: 0
  defp to_i(n) when is_integer(n), do: n
  defp to_i(n) when is_float(n), do: trunc(n)

  defp to_i(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> 0
    end
  end

  defp to_i(_), do: 0

  defp query_maps(sql, params \\ []) do
    case metadata_repo!() do
      nil ->
        []

      repo ->
        %{rows: rows, columns: columns} = repo.query!(sql, params, log: false)

        Enum.map(rows, fn row ->
          columns |> Enum.map(&to_string/1) |> Enum.zip(row) |> Map.new()
        end)
    end
  rescue
    _ -> []
  end

  defp metadata_repo!, do: Config.get().metadata_repo
  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)
end
