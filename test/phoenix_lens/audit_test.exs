defmodule PhoenixLens.AuditTest do
  use ExUnit.Case, async: false

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

  test "recording a query does not purge the audit log" do
    previous = Application.get_all_env(:phoenix_lens)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_lens),
          do: Application.delete_env(:phoenix_lens, key)

      for {key, value} <- previous, do: Application.put_env(:phoenix_lens, key, value)
    end)

    Application.put_env(:phoenix_lens, :repo, __MODULE__.FakeRepo)
    Application.delete_env(:phoenix_lens, :databases)

    assert :ok = Audit.record("select 1", nil, "ada", "primary", nil, nil, 1)

    assert_received {:query, sql}
    assert sql =~ "INSERT INTO phoenix_lens_audit"
    refute sql =~ "DELETE"
    refute_received {:query!, _sql, _params}
  end

  defmodule FakeRepo do
    def query(sql, _params, _opts \\ []) do
      send(self(), {:query, sql})
      {:ok, %{num_rows: 1, rows: [], columns: []}}
    end

    def query!(sql, params, _opts \\ []) do
      send(self(), {:query!, sql, params})
      %{num_rows: 0, rows: []}
    end
  end
end
