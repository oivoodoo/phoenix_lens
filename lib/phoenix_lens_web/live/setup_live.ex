defmodule PhoenixLensWeb.SetupLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.Operator

  @impl true
  def mount(_params, session, socket) do
    prefix = socket.assigns[:lens_prefix] || session["lens_prefix"] || "/lens"

    cond do
      not Operator.required?() ->
        {:ok, redirect(socket, to: prefix)}

      Operator.configured?() ->
        {:ok, redirect(socket, to: prefix <> "/login")}

      true ->
        smtp? = Operator.smtp_configured?()

        {:ok,
         socket
         |> assign(:page, :setup)
         |> assign(:page_title, "Set up Lens")
         |> assign(:error, nil)
         |> assign(:smtp?, smtp?)
         |> assign(:step, :account)
         |> assign(:pending, nil)
         |> assign(:username, "")
         |> assign(:email, "")}
    end
  end

  @impl true
  def handle_event("create", params, socket) do
    attrs = %{
      "username" => params["username"],
      "password" => params["password"],
      "email" => params["email"]
    }

    cond do
      params["password"] != params["password_confirm"] ->
        {:noreply, assign(socket, :error, "Passwords do not match")}

      socket.assigns.smtp? and blank?(attrs["email"]) ->
        {:noreply,
         assign(socket, :error, "Email is required so Lens can send a verification code")}

      socket.assigns.smtp? ->
        start_email_verify(socket, attrs)

      true ->
        finish_setup(socket, attrs)
    end
  end

  def handle_event("verify", %{"code" => code}, socket) do
    pending = socket.assigns.pending

    cond do
      is_nil(pending) ->
        {:noreply, assign(socket, :error, "Start setup again")}

      Operator.verify_email_code(pending["email"], code) ->
        finish_setup(socket, pending)

      true ->
        {:noreply, assign(socket, :error, "That code is not valid")}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, step: :account, error: nil, pending: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-unlock">
      <div class="lens-dash-card">
        <p class="lens-kicker">First boot</p>
        <h1>Create the Lens operator</h1>
        <p class="lens-muted">
          This account signs in to the standalone dashboard. There is only one operator.
        </p>

        <div :if={@error} class="lens-error">{@error}</div>

        <form
          :if={@step == :account}
          phx-submit="create"
          class="lens-modal-form"
          style="padding: 16px 0 0;"
        >
          <label>
            Username
            <input
              class="lens-field"
              type="text"
              name="username"
              value={@username}
              autocomplete="username"
              required
            />
          </label>
          <label>
            Password
            <input
              class="lens-field"
              type="password"
              name="password"
              autocomplete="new-password"
              minlength="10"
              required
            />
          </label>
          <label>
            Confirm password
            <input
              class="lens-field"
              type="password"
              name="password_confirm"
              autocomplete="new-password"
              minlength="10"
              required
            />
          </label>
          <label :if={@smtp?}>
            Email
            <input
              class="lens-field"
              type="email"
              name="email"
              value={@email}
              autocomplete="email"
              required
            />
          </label>
          <p :if={@smtp?} class="lens-muted">
            SMTP is configured. We will email a code to verify this address and use it as 2FA on sign-in.
          </p>
          <div class="lens-modal-actions">
            <button type="submit">{if @smtp?, do: "Send verification code", else: "Create operator"}</button>
          </div>
        </form>

        <form
          :if={@step == :verify}
          phx-submit="verify"
          class="lens-modal-form"
          style="padding: 16px 0 0;"
        >
          <p class="lens-muted">
            Enter the 6-digit code sent to {@pending["email"]}.
          </p>
          <label>
            Verification code
            <input
              class="lens-field"
              type="text"
              name="code"
              inputmode="numeric"
              autocomplete="one-time-code"
              placeholder="123456"
              maxlength="8"
            />
          </label>
          <div class="lens-modal-actions">
            <button type="button" phx-click="back" class="ghost">Back</button>
            <button type="submit">Verify email</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp start_email_verify(socket, attrs) do
    case Operator.validate_attrs(attrs) do
      {:ok, valid} ->
        case Operator.send_code(valid.email, :setup) do
          :ok ->
            {:noreply,
             socket
             |> assign(:step, :verify)
             |> assign(:error, nil)
             |> assign(:username, valid.username)
             |> assign(:email, valid.email)
             |> assign(:pending, attrs)}

          {:error, error} ->
            {:noreply, assign(socket, :error, error.message)}
        end

      {:error, error} ->
        {:noreply, assign(socket, :error, error.message)}
    end
  end

  defp finish_setup(socket, attrs) do
    case Operator.create(attrs) do
      {:ok, operator} ->
        token = Operator.issue_session_ticket(operator)
        prefix = socket.assigns.lens_prefix

        {:noreply,
         redirect(socket, to: prefix <> "/session/complete?t=" <> URI.encode_www_form(token))}

      {:error, error} ->
        {:noreply, assign(socket, :error, error.message)}
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
