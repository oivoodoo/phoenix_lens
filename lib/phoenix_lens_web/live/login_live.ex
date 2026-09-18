defmodule PhoenixLensWeb.LoginLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.Operator

  @impl true
  def mount(_params, session, socket) do
    prefix = socket.assigns[:lens_prefix] || session["lens_prefix"] || "/lens"

    cond do
      not Operator.required?() ->
        {:ok, redirect(socket, to: prefix)}

      not Operator.configured?() ->
        {:ok, redirect(socket, to: prefix <> "/setup")}

      session["lens_operator"] ->
        {:ok, redirect(socket, to: prefix)}

      true ->
        {:ok,
         socket
         |> assign(:page, :login)
         |> assign(:page_title, "Sign in · Lens")
         |> assign(:error, nil)
         |> assign(:step, :password)
         |> assign(:pending, nil)
         |> assign(:username, "")}
    end
  end

  @impl true
  def handle_event("login", %{"username" => username, "password" => password}, socket) do
    case Operator.authenticate(username, password) do
      {:ok, operator} ->
        if Operator.email_2fa?(operator) do
          case Operator.send_code(operator["email"], :login) do
            :ok ->
              {:noreply,
               socket
               |> assign(:step, :verify)
               |> assign(:error, nil)
               |> assign(:username, operator["username"])
               |> assign(
                 :pending,
                 Map.take(operator, ["id", "username", "email", "email_verified_at"])
               )}

            {:error, error} ->
              {:noreply, assign(socket, :error, error.message)}
          end
        else
          {:noreply, complete(socket, operator)}
        end

      {:error, error} ->
        {:noreply, assign(socket, :error, error.message)}
    end
  end

  def handle_event("verify", %{"code" => code}, socket) do
    operator = socket.assigns.pending

    cond do
      is_nil(operator) ->
        {:noreply, assign(socket, :error, "Sign in again")}

      Operator.verify_email_code(operator["email"], code) ->
        {:noreply, complete(socket, operator)}

      true ->
        {:noreply, assign(socket, :error, "That code is not valid")}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, step: :password, error: nil, pending: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lens-unlock">
      <div class="lens-dash-card">
        <p class="lens-kicker">Standalone</p>
        <h1>Sign in to Lens</h1>
        <p class="lens-muted">Use the operator account created on first boot.</p>

        <div :if={@error} class="lens-error">{@error}</div>

        <form
          :if={@step == :password}
          phx-submit="login"
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
              autocomplete="current-password"
              required
            />
          </label>
          <div class="lens-modal-actions">
            <button type="submit">Sign in</button>
          </div>
        </form>

        <form
          :if={@step == :verify}
          phx-submit="verify"
          class="lens-modal-form"
          style="padding: 16px 0 0;"
        >
          <p class="lens-muted">
            Email 2FA is on. Enter the code sent to the operator email.
          </p>
          <label>
            Sign-in code
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
            <button type="submit">Verify</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp complete(socket, operator) do
    token =
      Operator.issue_session_ticket(%{
        id: operator["id"] || operator[:id],
        username: operator["username"] || operator[:username]
      })

    prefix = socket.assigns.lens_prefix
    redirect(socket, to: prefix <> "/session/complete?t=" <> URI.encode_www_form(token))
  end
end
