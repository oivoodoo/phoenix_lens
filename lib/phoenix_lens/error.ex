defmodule PhoenixLens.Error do
  @moduledoc """
  Error returned by `PhoenixLens.run/2`.
  """

  defexception [:message, :kind]

  @type t :: %__MODULE__{
          message: String.t(),
          kind: :sql | :policy | :timeout | :read_only | :config
        }

  @impl true
  def message(%__MODULE__{message: message}), do: message

  def from_exception(%__MODULE__{} = error), do: error

  def from_exception(%DBConnection.ConnectionError{message: message}) do
    %__MODULE__{message: message, kind: :timeout}
  end

  def from_exception(%Postgrex.Error{} = error) do
    postgres = Map.get(error, :postgres) || %{}
    code = postgres[:code]

    kind =
      cond do
        code in [:read_only_sql_transaction, :insufficient_privilege] -> :read_only
        code == :query_canceled -> :timeout
        true -> :sql
      end

    %__MODULE__{message: Exception.message(error), kind: kind}
  end

  def from_exception(other) do
    %__MODULE__{message: Exception.message(other), kind: :sql}
  end
end
