defmodule PhoenixLens.DashboardsTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Dashboards

  test "slot_map packs two cards per row on a 12-col board" do
    assert Dashboards.slot_map(0) == %{"col" => 0, "row" => 0, "size_x" => 6, "size_y" => 5}
    assert Dashboards.slot_map(1) == %{"col" => 6, "row" => 0, "size_x" => 6, "size_y" => 5}
    assert Dashboards.slot_map(2) == %{"col" => 0, "row" => 5, "size_x" => 6, "size_y" => 5}
  end

  test "clamp_layout keeps cards on the board" do
    assert Dashboards.clamp_layout(%{"col" => -2, "row" => -1, "size_x" => 1, "size_y" => 1}) ==
             %{"col" => 0, "row" => 0, "size_x" => 3, "size_y" => 3}
  end

  test "clamp_layout at col 10 cannot overflow 12 columns" do
    layout = Dashboards.clamp_layout(%{"col" => 10, "row" => 0, "size_x" => 8, "size_y" => 4})
    assert layout["col"] + layout["size_x"] <= 12
    assert layout["size_x"] >= 3
  end

  test "overlaps? detects intersecting rectangles" do
    a = %{"col" => 0, "row" => 0, "size_x" => 6, "size_y" => 5}
    b = %{"col" => 6, "row" => 0, "size_x" => 6, "size_y" => 5}
    c = %{"col" => 2, "row" => 1, "size_x" => 6, "size_y" => 5}
    refute Dashboards.overlaps?(a, b)
    assert Dashboards.overlaps?(a, c)
  end

  test "pack spreads stacked origin cards" do
    cards = [
      %{"id" => 1, "col" => 0, "row" => 0, "size_x" => 6, "size_y" => 5},
      %{"id" => 2, "col" => 0, "row" => 0, "size_x" => 6, "size_y" => 5},
      %{"id" => 3, "col" => 0, "row" => 0, "size_x" => 6, "size_y" => 5}
    ]

    packed = Dashboards.pack(cards)
    assert Enum.map(packed, &{&1["col"], &1["row"]}) == [{0, 0}, {6, 0}, {0, 5}]
  end

  test "pack leaves a valid layout alone" do
    cards = [
      %{"id" => 1, "col" => 0, "row" => 0, "size_x" => 6, "size_y" => 5},
      %{"id" => 2, "col" => 6, "row" => 0, "size_x" => 6, "size_y" => 8}
    ]

    packed = Dashboards.pack(cards)
    assert Enum.map(packed, &{&1["col"], &1["row"], &1["size_y"]}) == [{0, 0, 5}, {6, 0, 8}]
  end

  test "next_slot finds a free half-width cell" do
    cards = [
      %{"col" => 0, "row" => 0, "size_x" => 6, "size_y" => 5},
      %{"col" => 6, "row" => 0, "size_x" => 6, "size_y" => 5}
    ]

    assert Dashboards.next_slot(cards) == %{"col" => 0, "row" => 5, "size_x" => 6, "size_y" => 5}
  end
end
