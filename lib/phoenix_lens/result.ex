defmodule PhoenixLens.Result do
  @moduledoc """
  A policy-applied query result. There is no unmasked variant.
  """

  @enforce_keys [:columns, :rows, :masked_columns]
  defstruct columns: [],
            rows: [],
            masked_columns: [],
            truncated: false,
            num_rows: 0,
            duration_ms: 0,
            database_id: "primary",
            sql: nil

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[term()]],
          masked_columns: [String.t()],
          truncated: boolean(),
          num_rows: non_neg_integer(),
          duration_ms: non_neg_integer(),
          database_id: String.t(),
          sql: String.t() | nil
        }

  @redacted_label "[redacted]"

  def redacted_label, do: @redacted_label

  @doc """
  Make every cell Jason-safe so LiveView can push results over the socket.

  Postgrex returns uuid/bytea as raw binaries; those crash `Jason.encode!/1`.
  """
  def sanitize(%__MODULE__{} = result) do
    %{result | rows: Enum.map(result.rows, fn row -> Enum.map(row, &sanitize_cell/1) end)}
  end

  def sanitize_cell(:redacted), do: :redacted
  def sanitize_cell(nil), do: nil
  def sanitize_cell(value) when is_boolean(value) or is_number(value), do: value
  def sanitize_cell(%Decimal{} = d), do: Decimal.to_string(d)
  def sanitize_cell(%Date{} = d), do: Date.to_iso8601(d)
  def sanitize_cell(%Time{} = t), do: Time.to_iso8601(t)
  def sanitize_cell(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def sanitize_cell(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  def sanitize_cell(value) when is_binary(value), do: display_binary(value)
  def sanitize_cell(value) when is_atom(value), do: Atom.to_string(value)
  def sanitize_cell(value) when is_list(value), do: Enum.map(value, &sanitize_cell/1)

  def sanitize_cell(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {k, v} -> {sanitize_key(k), sanitize_cell(v)} end)
  end

  def sanitize_cell(value), do: inspect(value)

  def display_cell(:redacted), do: @redacted_label
  def display_cell(nil), do: ""
  def display_cell(%Decimal{} = d), do: Decimal.to_string(d)
  def display_cell(%Date{} = d), do: Date.to_iso8601(d)
  def display_cell(%Time{} = t), do: Time.to_iso8601(t)
  def display_cell(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def display_cell(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  def display_cell(value) when is_binary(value), do: display_binary(value)
  def display_cell(value) when is_number(value), do: to_string(value)
  def display_cell(value) when is_boolean(value), do: to_string(value)
  def display_cell(value), do: inspect(value)

  defp display_binary(value) do
    cond do
      String.valid?(value) ->
        value

      byte_size(value) == 16 ->
        format_uuid(value)

      true ->
        "\\x" <> Base.encode16(value, case: :lower)
    end
  end

  defp format_uuid(<<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2), e::binary-size(6)>>) do
    [a, b, c, d, e]
    |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end

  defp sanitize_key(k) when is_atom(k), do: Atom.to_string(k)
  defp sanitize_key(k) when is_binary(k), do: display_binary(k)
  defp sanitize_key(k), do: to_string(k)
end
