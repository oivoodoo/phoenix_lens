defmodule PhoenixLens.ResultTest do
  use ExUnit.Case, async: true

  alias PhoenixLens.Result

  test "display_cell keeps UTF-8 text" do
    assert Result.display_cell("hello") == "hello"
  end

  test "display_cell formats 16-byte binaries as UUIDs" do
    uuid = <<93, 250, 226, 107, 45, 199, 75, 193, 163, 103, 245, 105, 197, 69, 215, 36>>
    assert Result.display_cell(uuid) == "5dfae26b-2dc7-4bc1-a367-f569c545d724"
  end

  test "display_cell hex-encodes other non-UTF-8 binaries" do
    assert Result.display_cell(<<0xFA, 0x00, 0xFF>>) == "\\xfa00ff"
  end

  test "sanitize makes uuid/bytea cells Jason-safe" do
    uuid = <<93, 250, 226, 107, 45, 199, 75, 193, 163, 103, 245, 105, 197, 69, 215, 36>>

    result =
      Result.sanitize(%Result{
        columns: ["uuid", "blob", "email"],
        rows: [[uuid, <<0xFA, 0x00>>, :redacted]],
        masked_columns: ["email"]
      })

    assert hd(result.rows) == ["5dfae26b-2dc7-4bc1-a367-f569c545d724", "\\xfa00", :redacted]
    assert {:ok, _} = Jason.encode(result.rows)
  end
end
