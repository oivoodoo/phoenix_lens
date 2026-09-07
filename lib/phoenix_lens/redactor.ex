defmodule PhoenixLens.Redactor do
  @moduledoc false

  @email ~r/'[^']*@[A-Za-z0-9.-]+\.[A-Za-z]{2,}[^']*'/
  @phone ~r/'[0-9][0-9+\-().\s]{6,}[0-9]'/

  def sql(nil), do: nil

  def sql(sql) when is_binary(sql) do
    sql
    |> String.replace(@email, "'[redacted]'")
    |> String.replace(@phone, "'[redacted]'")
  end

  def sql(other), do: to_string(other)

  def hash(sql) when is_binary(sql) do
    :crypto.hash(:sha256, sql) |> Base.encode16(case: :lower)
  end

  def actor(nil), do: "anonymous"

  def actor(%{id: id, kind: :mcp}) do
    "mcp:#{id}"
  end

  def actor(%{id: id}) do
    "user:#{id}"
  end

  def actor(id) when is_integer(id) or is_binary(id) or is_atom(id) do
    to_string(id)
  end

  def actor(other) do
    other |> inspect() |> String.slice(0, 120)
  end
end
