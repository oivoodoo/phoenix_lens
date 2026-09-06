defmodule PhoenixLens.AuditTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Audit

  test "page is empty without a metadata repo" do
    page = Audit.page(1, 25)
    assert page.entries == []
    assert page.total == 0
    assert page.page == 1
    assert page.from == 0
    assert page.to == 0
  end

  test "formats timestamps without fractional seconds" do
    assert Audit.format_when(~N[2026-09-06 17:15:59]) == "2026-09-06 17:15"
    assert Audit.format_when("2026-09-06T17:15:59.410878") == "2026-09-06 17:15"
  end

  test "clamps page size" do
    page = Audit.page(99, 1000)
    assert page.per_page == 100
    assert page.page == 1
  end
end
