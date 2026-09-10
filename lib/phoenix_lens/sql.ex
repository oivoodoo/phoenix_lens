defmodule PhoenixLens.SQL do
  @moduledoc false

  @forbidden ~w(
    insert update delete merge drop alter create grant revoke truncate
    copy call do listen notify vacuum reindex cluster lock
    attach detach install load export import pragma checkpoint
    upsert unload overwrite undrop
  )

  @write_heads ~w(
    INSERT UPDATE DELETE MERGE DROP ALTER CREATE GRANT REVOKE TRUNCATE
    COPY CALL REPLACE UPSERT UNLOAD ATTACH DETACH INSTALL LOAD
    VACUUM REINDEX CLUSTER LOCK BEGIN COMMIT ROLLBACK DECLARE
  )

  @write_message "Lens is view-only. DELETE, UPDATE, INSERT, and other writes are not allowed."

  @doc """
  Normalize and reject anything that is not a single read-only statement.
  """
  def validate(sql) when is_binary(sql) do
    stripped = strip_comments(sql) |> String.trim()

    cond do
      stripped == "" ->
        {:error, %PhoenixLens.Error{message: "SQL is empty", kind: :sql}}

      extra_statement?(stripped) ->
        {:error, %PhoenixLens.Error{message: "one statement only", kind: :sql}}

      true ->
        body = String.trim_trailing(stripped, ";") |> String.trim()
        classify(body)
    end
  end

  def validate(_), do: {:error, %PhoenixLens.Error{message: "SQL is empty", kind: :sql}}

  defp classify(body) do
    keyword = first_keyword(body)

    cond do
      keyword in @write_heads or forbidden?(body) or locking_clause?(body) ->
        {:error, %PhoenixLens.Error{message: @write_message, kind: :read_only}}

      keyword in ["SELECT", "WITH"] ->
        {:ok, body}

      keyword == "EXPLAIN" ->
        validate_explain(body)

      true ->
        {:error,
         %PhoenixLens.Error{
           message: "only SELECT / WITH (or EXPLAIN of those) is allowed",
           kind: :read_only
         }}
    end
  end

  defp validate_explain(body) do
    rest =
      body
      |> String.replace(~r/\AEXPLAIN\s+(ANALYZE\s+)?(VERBOSE\s+)?/i, "")
      |> String.trim()

    inner = first_keyword(rest)

    if inner in ["SELECT", "WITH"] and not forbidden?(rest) and not locking_clause?(rest) do
      {:ok, body}
    else
      {:error,
       %PhoenixLens.Error{
         message: "EXPLAIN is only allowed for SELECT / WITH",
         kind: :read_only
       }}
    end
  end

  @doc """
  Table references from FROM / JOIN, including optional source qualifiers.
  """
  def table_refs(sql) when is_binary(sql) do
    sql
    |> strip_comments()
    |> String.replace(~r/'([^']|'')*'/, "''")
    |> then(
      &Regex.scan(
        ~r/(?:FROM|JOIN)\s+((?:"[^"]+"|[A-Za-z_][A-Za-z0-9_]*)(?:\s*\.\s*(?:"[^"]+"|[A-Za-z_][A-Za-z0-9_]*)){0,2})/i,
        &1
      )
    )
    |> Enum.map(fn [_, ref] -> parse_table_ref(ref) end)
    |> Enum.reject(&is_nil(&1.table))
    |> Enum.uniq()
  end

  def table_refs(_), do: []

  defp parse_table_ref(ref) do
    parts =
      ref
      |> String.replace("\"", "")
      |> String.split(".")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.downcase/1)

    case parts do
      [table] -> %{source: nil, table: table}
      [source, table] -> %{source: source, table: table}
      [source, _schema, table] -> %{source: source, table: table}
      _ -> %{source: nil, table: nil}
    end
  end

  def first_keyword(sql) do
    case Regex.run(~r/\A([A-Za-z]+)/, strip_comments(sql) |> String.trim()) do
      [_, word] -> String.upcase(word)
      _ -> ""
    end
  end

  def forbidden?(sql) do
    text = strip_strings(strip_comments(sql))

    Enum.any?(@forbidden, fn word ->
      Regex.match?(~r/(^|[^A-Za-z0-9_])#{word}([^A-Za-z0-9_]|$)/i, text)
    end) or Regex.match?(~r/(^|[^A-Za-z0-9_])into([^A-Za-z0-9_]|$)/i, text)
  end

  def locking_clause?(sql) do
    text = strip_strings(strip_comments(sql))

    Regex.match?(
      ~r/(^|[^A-Za-z0-9_])for\s+(no\s+key\s+)?(update|share|key\s+share)([^A-Za-z0-9_]|$)/i,
      text
    )
  end

  def extra_statement?(sql) do
    sql
    |> String.trim()
    |> String.trim_trailing(";")
    |> split_statements()
    |> Enum.reject(&(&1 == ""))
    |> length() > 1
  end

  def strip_comments(sql) do
    sql
    |> strip_block_comments()
    |> strip_line_comments()
  end

  defp strip_block_comments(sql) do
    Regex.replace(~r{/\*.*?\*/}s, sql, " ")
  end

  defp strip_line_comments(sql) do
    sql
    |> String.split("\n")
    |> Enum.map(fn line ->
      case split_unquoted(line, "--") do
        {keep, _rest} -> keep
        :none -> line
      end
    end)
    |> Enum.join("\n")
  end

  def strip_strings(sql) do
    sql
    |> String.replace(~r/'([^']|'')*'/, "''")
    |> String.replace(~r/"([^"]|"")*"/, "\"\"")
    |> String.replace(~r/\$\$.*?\$\$/s, "$$ $$")
  end

  @doc """
  Best-effort SELECT-list items of the outermost query.
  """
  def select_items(sql) do
    body = strip_comments(sql) |> String.trim_trailing(";") |> String.trim()
    body = unwrap_explain(body)

    case outermost_select_list(body) do
      nil -> []
      list -> split_select_items(list)
    end
  end

  @doc """
  Map Postgres result column names to origin identifiers using the SELECT list.
  """
  def column_origins(sql, result_names) when is_list(result_names) do
    items = select_items(sql)

    parsed =
      Enum.map(items, fn item ->
        {output, origin, computed?} = describe_item(item)
        %{output: output, origin: origin, computed?: computed?, sql: item}
      end)

    if match_by_position?(parsed, result_names) do
      Enum.zip(result_names, parsed)
      |> Enum.map(fn {name, meta} ->
        %{name: name, origin: meta.origin, computed?: meta.computed?, sql: meta.sql}
      end)
    else
      Enum.map(result_names, fn name ->
        meta = Enum.find(parsed, fn m -> down(m.output) == down(name) end)

        %{
          name: name,
          origin: meta && meta.origin,
          computed?: if(meta, do: meta.computed?, else: true),
          sql: meta && meta.sql
        }
      end)
    end
  end

  defp match_by_position?(parsed, result_names) do
    length(parsed) == length(result_names) and
      not Enum.any?(parsed, fn m -> m.output in ["*", nil] end)
  end

  def describe_item(item) do
    item = String.trim(item)
    {expr, alias_} = split_alias(item)
    expr = String.trim(expr)
    output = alias_ || bare_identifier(expr)
    computed? = not simple_column?(expr)
    origin = if computed?, do: nil, else: bare_identifier(expr)
    {output, origin, computed?}
  end

  def contains_identifier?(sql, name) when is_binary(name) do
    ident = Regex.escape(name)
    Regex.match?(~r/(^|[^A-Za-z0-9_])#{ident}([^A-Za-z0-9_]|$)/i, sql)
  end

  defp unwrap_explain(body) do
    String.replace(body, ~r/\AEXPLAIN\s+(ANALYZE\s+)?(VERBOSE\s+)?/i, "")
  end

  defp outermost_select_list(sql) do
    {start, _len} = find_main_select(sql) || {nil, nil}

    if is_nil(start) do
      nil
    else
      after_select = String.slice(sql, (start + 6)..-1//1)
      take_until_from(after_select)
    end
  end

  defp find_main_select(sql) do
    find_at_depth(sql, "SELECT", 0, 0, false)
  end

  defp find_at_depth(sql, _word, idx, _depth, _in_with) when idx >= byte_size(sql), do: nil

  defp find_at_depth(sql, word, idx, depth, in_with) do
    rest = binary_part(sql, idx, byte_size(sql) - idx)

    cond do
      String.starts_with?(rest, "'") ->
        skip = skip_quote(sql, idx, "'")
        find_at_depth(sql, word, skip, depth, in_with)

      String.starts_with?(rest, "\"") ->
        skip = skip_quote(sql, idx, "\"")
        find_at_depth(sql, word, skip, depth, in_with)

      String.starts_with?(rest, "(") ->
        find_at_depth(sql, word, idx + 1, depth + 1, in_with)

      String.starts_with?(rest, ")") ->
        find_at_depth(sql, word, idx + 1, max(depth - 1, 0), in_with)

      depth == 0 and word_at?(rest, "WITH") ->
        find_at_depth(sql, word, idx + 4, depth, true)

      depth == 0 and word_at?(rest, "SELECT") ->
        {idx, 6}

      true ->
        find_at_depth(sql, word, idx + 1, depth, in_with)
    end
  end

  defp word_at?(rest, word) do
    size = byte_size(word)

    String.upcase(String.slice(rest, 0, size)) == word and
      not ident_char?(safe_at(rest, size))
  end

  defp ident_char?(<<c>>) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_, do: true
  defp ident_char?(_), do: false

  defp safe_at(bin, i) when i >= byte_size(bin), do: <<0>>
  defp safe_at(bin, i), do: binary_part(bin, i, 1)

  defp skip_quote(sql, idx, q) do
    rest = binary_part(sql, idx + 1, byte_size(sql) - idx - 1)

    case :binary.match(rest, q) do
      {pos, _} -> idx + 1 + pos + 1
      :nomatch -> byte_size(sql)
    end
  end

  defp take_until_from(sql) do
    take_until_from(sql, 0, 0, [])
  end

  defp take_until_from(sql, idx, _depth, acc) when idx >= byte_size(sql) do
    acc |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()
  end

  defp take_until_from(sql, idx, depth, acc) do
    rest = binary_part(sql, idx, byte_size(sql) - idx)

    cond do
      String.starts_with?(rest, "'") ->
        skip = skip_quote(sql, idx, "'")
        chunk = binary_part(sql, idx, skip - idx)
        take_until_from(sql, skip, depth, [chunk | acc])

      String.starts_with?(rest, "\"") ->
        skip = skip_quote(sql, idx, "\"")
        chunk = binary_part(sql, idx, skip - idx)
        take_until_from(sql, skip, depth, [chunk | acc])

      String.starts_with?(rest, "(") ->
        take_until_from(sql, idx + 1, depth + 1, ["(" | acc])

      String.starts_with?(rest, ")") ->
        take_until_from(sql, idx + 1, max(depth - 1, 0), [")" | acc])

      depth == 0 and terminator?(rest) ->
        acc |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

      true ->
        <<c, _::binary>> = rest
        take_until_from(sql, idx + 1, depth, [<<c>> | acc])
    end
  end

  defp terminator?(rest) do
    Enum.any?(
      ~w(FROM WHERE GROUP HAVING ORDER LIMIT WINDOW UNION EXCEPT INTERSECT FETCH OFFSET FOR INTO),
      &word_at?(rest, &1)
    )
  end

  defp split_select_items(list) do
    split_depth(list, 0, 0, [], [])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_depth(sql, idx, _depth, current, acc) when idx >= byte_size(sql) do
    item = current |> Enum.reverse() |> IO.iodata_to_binary()
    Enum.reverse([item | acc])
  end

  defp split_depth(sql, idx, depth, current, acc) do
    rest = binary_part(sql, idx, byte_size(sql) - idx)

    cond do
      String.starts_with?(rest, "'") ->
        skip = skip_quote(sql, idx, "'")
        chunk = binary_part(sql, idx, skip - idx)
        split_depth(sql, skip, depth, [chunk | current], acc)

      String.starts_with?(rest, "\"") ->
        skip = skip_quote(sql, idx, "\"")
        chunk = binary_part(sql, idx, skip - idx)
        split_depth(sql, skip, depth, [chunk | current], acc)

      String.starts_with?(rest, "(") ->
        split_depth(sql, idx + 1, depth + 1, ["(" | current], acc)

      String.starts_with?(rest, ")") ->
        split_depth(sql, idx + 1, max(depth - 1, 0), [")" | current], acc)

      depth == 0 and String.starts_with?(rest, ",") ->
        item = current |> Enum.reverse() |> IO.iodata_to_binary()
        split_depth(sql, idx + 1, 0, [], [item | acc])

      true ->
        <<c, _::binary>> = rest
        split_depth(sql, idx + 1, depth, [<<c>> | current], acc)
    end
  end

  defp split_alias(item) do
    case Regex.run(~r/\s+AS\s+("(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_]*)\s*\z/i, item) do
      [full, alias_] ->
        expr = String.slice(item, 0, byte_size(item) - byte_size(full))
        {expr, unquote_ident(alias_)}

      nil ->
        {item, nil}
    end
  end

  defp simple_column?(expr) do
    Regex.match?(
      ~r/\A((?:"(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_]*)\.)?(?:"(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_]*)\z/,
      String.trim(expr)
    )
  end

  defp bare_identifier(expr) do
    expr = String.trim(expr)

    case Regex.run(~r/(?:"(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_]*)\z/, expr) do
      [ident] -> unquote_ident(ident)
      _ -> nil
    end
  end

  defp unquote_ident(<<?", rest::binary>>) do
    rest |> String.trim_trailing("\"") |> String.replace("\"\"", "\"")
  end

  defp unquote_ident(ident), do: ident

  defp down(nil), do: nil
  defp down(name), do: String.downcase(name)

  defp split_unquoted(line, marker) do
    case :binary.match(line, marker) do
      :nomatch ->
        :none

      {pos, _} ->
        prefix = binary_part(line, 0, pos)

        if rem(count_quotes(prefix), 2) == 1 do
          :none
        else
          {prefix, binary_part(line, pos, byte_size(line) - pos)}
        end
    end
  end

  defp count_quotes(str), do: str |> String.graphemes() |> Enum.count(&(&1 == "'"))

  defp split_statements(sql) do
    split_statements(sql, 0, 0, [], [])
  end

  defp split_statements(sql, idx, _depth, current, acc) when idx >= byte_size(sql) do
    item = current |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()
    Enum.reverse([item | acc])
  end

  defp split_statements(sql, idx, depth, current, acc) do
    rest = binary_part(sql, idx, byte_size(sql) - idx)

    cond do
      String.starts_with?(rest, "'") ->
        skip = skip_quote(sql, idx, "'")
        chunk = binary_part(sql, idx, skip - idx)
        split_statements(sql, skip, depth, [chunk | current], acc)

      String.starts_with?(rest, "(") ->
        split_statements(sql, idx + 1, depth + 1, ["(" | current], acc)

      String.starts_with?(rest, ")") ->
        split_statements(sql, idx + 1, max(depth - 1, 0), [")" | current], acc)

      depth == 0 and String.starts_with?(rest, ";") ->
        item = current |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()
        split_statements(sql, idx + 1, 0, [], [item | acc])

      true ->
        <<c, _::binary>> = rest
        split_statements(sql, idx + 1, depth, [<<c>> | current], acc)
    end
  end
end
