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

  def display_cell(:redacted), do: @redacted_label
  def display_cell(nil), do: ""
  def display_cell(%Decimal{} = d), do: Decimal.to_string(d)
  def display_cell(%Date{} = d), do: Date.to_iso8601(d)
  def display_cell(%Time{} = t), do: Time.to_iso8601(t)
  def display_cell(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def display_cell(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  def display_cell(value) when is_binary(value), do: value
  def display_cell(value) when is_number(value), do: to_string(value)
  def display_cell(value) when is_boolean(value), do: to_string(value)
  def display_cell(value), do: inspect(value)
end
