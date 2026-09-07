defmodule PhoenixLens.Alerts.Mailer do
  @moduledoc false

  def available? do
    Code.ensure_loaded?(:gen_smtp_client) and
      function_exported?(:gen_smtp_client, :send_blocking, 2)
  end

  def missing_message do
    "Email alerts require {:gen_smtp, \"~> 1.2\"} in the host mix.exs, then mix deps.get"
  end

  def send(smtp, to, subject, body) when is_map(smtp) and is_binary(to) do
    unless available?() do
      {:error, missing_message()}
    else
      from = smtp["from"] || smtp[:from]
      host = smtp["host"] || smtp[:host]
      port = smtp["port"] || smtp[:port] || 587
      user = smtp["username"] || smtp[:username]
      pass = smtp["password"] || smtp[:password]
      tls? = smtp["tls"] || smtp[:tls] || true

      mime = rfc822(from, to, subject, body)

      opts =
        [
          relay: to_charlist(host),
          port: port,
          tls: if(tls?, do: :always, else: :never)
        ]
        |> maybe_auth(user, pass)

      case :gen_smtp_client.send_blocking({from, [to], mime}, opts) do
        receipt when is_binary(receipt) -> :ok
        {:error, reason} -> {:error, format(reason)}
        {:error, _, reason} -> {:error, format(reason)}
        other -> {:error, format(other)}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp maybe_auth(opts, user, pass)
       when is_binary(user) and user != "" and is_binary(pass) and pass != "" do
    Keyword.merge(opts, username: user, password: pass, auth: :always)
  end

  defp maybe_auth(opts, _, _), do: opts

  defp rfc822(from, to, subject, body) do
    [
      "From: #{from}",
      "To: #{to}",
      "Subject: #{encode_subject(subject)}",
      "MIME-Version: 1.0",
      "Content-Type: text/plain; charset=UTF-8",
      "Content-Transfer-Encoding: 8bit",
      "",
      body || ""
    ]
    |> Enum.join("\r\n")
  end

  defp encode_subject(subject) do
    subject
    |> to_string()
    |> String.replace(~r/[\r\n]+/, " ")
    |> String.slice(0, 180)
  end

  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end
