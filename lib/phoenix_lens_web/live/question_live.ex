defmodule PhoenixLensWeb.QuestionLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Alerts, Autocomplete, Dashboards, Integrations, Questions, Query}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Questions.get(id) do
      {:ok, question} ->
        {result, error} = run(question, socket)

        {:ok,
         socket
         |> assign(:page, :questions)
         |> assign(:page_title, "#{question["name"]} · Lens")
         |> assign(:question, question)
         |> assign(:sql, question["sql"])
         |> assign(:name, question["name"])
         |> assign(:viz, question["viz"])
         |> assign(:result, result)
         |> assign(:error, error)
         |> assign(:editor_open, true)
         |> assign(:ac, Autocomplete.payload())
         |> assign(:dashboards, Dashboards.list())
         |> assign(:alert_modal, false)
         |> assign(:alert_error, nil)
         |> refresh_alerts(question["id"])}

      {:error, error} ->
        {:ok,
         socket
         |> assign(:page, :questions)
         |> assign(:question, nil)
         |> assign(:error, error)
         |> put_flash(:error, error.message)}
    end
  end

  def mount(params, _session, socket) do
    q = params["q"] || ""

    questions =
      Questions.list()
      |> maybe_filter(q)

    {:ok,
     socket
     |> assign(:page, :questions)
     |> assign(:page_title, "Questions · Lens")
     |> assign(:questions, questions)
     |> assign(:query, q)
     |> assign(:question, :index)}
  end

  @impl true
  def handle_info({:preview_viz, viz}, socket) do
    {:noreply, assign(socket, :viz, viz)}
  end

  @impl true
  def handle_event("run", params, socket) do
    sql = params["sql"] || socket.assigns.sql
    q = Map.put(socket.assigns.question, "sql", sql)
    {result, error} = run(q, socket)
    {:noreply, socket |> assign(:sql, sql) |> assign(:result, result) |> assign(:error, error)}
  end

  def handle_event("save", params, socket) do
    q = socket.assigns.question

    case Questions.save(%{
           id: q["id"],
           name: params["name"] || socket.assigns.name,
           sql: params["sql"] || socket.assigns.sql,
           viz: params["viz"] || socket.assigns.viz,
           database_id: q["database_id"]
         }) do
      {:ok, question} ->
        {:noreply,
         socket
         |> assign(:question, question)
         |> assign(:sql, question["sql"])
         |> assign(:name, question["name"])
         |> put_flash(:info, "Saved")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  def handle_event("delete", _params, socket) do
    Questions.delete(socket.assigns.question["id"])
    {:noreply, push_navigate(socket, to: lens_path(socket, "/questions"))}
  end

  def handle_event("pin", %{"dashboard_id" => dashboard_id}, socket) do
    case Dashboards.add_card(dashboard_id, socket.assigns.question["id"]) do
      {:ok, dash} ->
        {:noreply, put_flash(socket, :info, "Pinned to #{dash["name"]}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  def handle_event("change", params, socket) do
    {:noreply,
     socket
     |> assign(:sql, params["sql"] || socket.assigns.sql)
     |> assign(:name, params["name"] || socket.assigns.name)
     |> assign(:viz, params["viz"] || socket.assigns.viz)}
  end

  def handle_event("toggle-editor", _params, socket) do
    {:noreply, assign(socket, :editor_open, !socket.assigns.editor_open)}
  end

  def handle_event("open_alert", _params, socket) do
    {:noreply, socket |> assign(:alert_modal, true) |> assign(:alert_error, nil)}
  end

  def handle_event("close_alert", _params, socket) do
    {:noreply, assign(socket, :alert_modal, false)}
  end

  def handle_event("save_alert", params, socket) do
    q = socket.assigns.question

    attrs = %{
      question_id: q["id"],
      condition: params["condition"],
      threshold: params["threshold"],
      schedule: params["schedule"],
      once: params["once"],
      emails: params["emails"],
      webhook_ids: List.wrap(params["webhook_id"] || params["webhook_id[]"])
    }

    case Alerts.save(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:alert_modal, false)
         |> assign(:alert_error, nil)
         |> put_flash(:info, "Alert created")
         |> refresh_alerts(q["id"])}

      {:error, error} ->
        {:noreply, assign(socket, :alert_error, error.message)}
    end
  end

  def handle_event("delete_alert", %{"id" => id}, socket) do
    _ = Alerts.delete(id)
    q = socket.assigns.question
    {:noreply, socket |> put_flash(:info, "Alert deleted") |> refresh_alerts(q["id"])}
  end

  def handle_event("run_alert", %{"id" => id}, socket) do
    case PhoenixLens.Alerts.Runner.run_one(id, force: true, actor: socket.assigns.lens_actor) do
      {:ok, %{fired: true}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Alert sent")
         |> refresh_alerts(socket.assigns.question["id"])}

      {:ok, %{fired: false}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Checked — condition not met, nothing sent")
         |> refresh_alerts(socket.assigns.question["id"])}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(%{question: :index} = assigns) do
    ~H"""
    <div class="lens-browse">
      <header class="lens-browse-head">
        <h1>Questions</h1>
        <a class="lens-ask-btn" href={"#{@lens_prefix}/ask"}>✦ Ask a question</a>
      </header>
      <%= if @questions == [] do %>
        <p class="lens-empty">No saved questions yet.</p>
      <% else %>
        <div class="lens-item-list">
          <a :for={q <- @questions} class="lens-item" href={"#{@lens_prefix}/questions/#{q["id"]}"}>
            <span class="lens-item-icon" aria-hidden="true">📊</span>
            <span>
              <strong>{q["name"]}</strong>
              <span class="lens-muted">{q["viz"]}</span>
            </span>
          </a>
        </div>
      <% end %>
    </div>
    """
  end

  def render(%{question: nil} = assigns) do
    ~H"""
    <h1>Question</h1>
    <p class="lens-error">{@error && @error.message}</p>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="lens-question">
      <header class="lens-question-head">
        <input
          class="lens-title-input"
          form="q-form"
          type="text"
          name="name"
          value={@name}
          autocomplete="off"
        />
        <div class="lens-question-toolbar">
          <div class="lens-toolbar-group">
            <button
              type="button"
              class={if(@editor_open, do: "ghost is-on", else: "ghost")}
              phx-click="toggle-editor"
              aria-pressed={@editor_open}
            >
              Editor
            </button>
            <a
              class="ghost btn-link"
              href={"#{@lens_prefix}/questions/#{@question["id"]}/csv"}
            >
              Export
            </a>
            <button type="button" class="ghost" phx-click="open_alert">Alert</button>
          </div>
          <div class="lens-toolbar-group">
            <button
              type="button"
              class="ghost"
              phx-click="delete"
              data-confirm="Delete this question?"
            >
              Delete
            </button>
            <button type="submit" form="q-form">Save</button>
          </div>
        </div>
      </header>

      <form id="q-form" phx-submit="save" phx-change="change" class="lens-ask">
        <SqlEditor.editor
          :if={@editor_open}
          id={"lens-sql-q-#{@question["id"]}"}
          name="sql"
          value={@sql}
          catalog={@ac}
        />
      </form>

      <%= if @dashboards != [] do %>
        <form phx-submit="pin" class="lens-inline">
          <select name="dashboard_id" class="lens-field">
            <option :for={d <- @dashboards} value={d["id"]}>{d["name"]}</option>
          </select>
          <button type="submit" class="ghost">Pin to dashboard</button>
        </form>
      <% end %>

      <section :if={@alerts != []} class="lens-alert-list">
        <p class="lens-kicker">Alerts</p>
        <div :for={alert <- @alerts} class="lens-alert-row">
          <span>
            <strong>{condition_label(alert)}</strong>
            <span class="lens-muted"> · {alert["schedule"]} · {dest_label(alert)}</span>
          </span>
          <span class="lens-muted">{alert["last_status"] || "never run"}</span>
          <button type="button" class="ghost tiny" phx-click="run_alert" phx-value-id={alert["id"]}>
            Send now
          </button>
          <button type="button" class="ghost tiny" phx-click="delete_alert" phx-value-id={alert["id"]}>
            Delete
          </button>
        </div>
      </section>

      <%= if @error do %>
        <div class="lens-error">{@error.message}</div>
      <% end %>

      <section class="lens-viz-card">
        <%= if @result do %>
          <.live_component
            module={PhoenixLensWeb.ResultPreview}
            id={"q-preview-#{@question["id"]}"}
            result={@result}
            viz={@viz}
          />
        <% end %>
      </section>

      <div
        :if={@alert_modal}
        class="lens-modal-backdrop"
        phx-window-keydown="close_alert"
        phx-key="escape"
      >
        <div class="lens-modal" role="dialog" aria-modal="true">
          <header class="lens-modal-head">
            <h2>Create an alert</h2>
            <button type="button" class="ghost icon" phx-click="close_alert" aria-label="Close">×</button>
          </header>
          <form phx-submit="save_alert" class="lens-modal-form">
            <div :if={@alert_error} class="lens-error">{@alert_error}</div>
            <label>
              When
              <select class="lens-field" name="condition">
                <option value="rows">the question returns any rows</option>
                <option value="no_rows">the question returns no rows</option>
                <option value="above">a number goes above a goal</option>
                <option value="below">a number goes below a goal</option>
              </select>
            </label>
            <label>
              Goal (for above/below)
              <input class="lens-field" type="text" name="threshold" placeholder="100" />
            </label>
            <label>
              Check
              <select class="lens-field" name="schedule">
                <option value="1m">every minute</option>
                <option value="5m">every 5 minutes</option>
                <option value="15m">every 15 minutes</option>
                <option value="1h" selected>hourly</option>
                <option value="6h">every 6 hours</option>
                <option value="1d">daily</option>
              </select>
            </label>
            <label>
              Email recipients
              <input class="lens-field" type="text" name="emails" placeholder="ops@example.com" />
            </label>
            <fieldset :if={@webhooks != []} class="lens-hook-picks">
              <legend>Webhooks</legend>
              <label :for={hook <- @webhooks} class="lens-check">
                <input type="checkbox" name="webhook_id[]" value={hook["id"]} />
                {hook["name"]}
              </label>
            </fieldset>
            <p :if={@webhooks == []} class="lens-muted">
              Add a webhook in <a href={"#{@lens_prefix}/settings/integrations"}>Integrations</a>.
            </p>
            <label class="lens-check">
              <input type="checkbox" name="once" value="true" /> Only send once, then disable
            </label>
            <div class="lens-modal-actions">
              <button type="button" class="ghost" phx-click="close_alert">Cancel</button>
              <button type="submit">Create alert</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp refresh_alerts(socket, question_id) do
    socket
    |> assign(:alerts, Alerts.list_for_question(question_id))
    |> assign(:webhooks, Integrations.webhooks())
  end

  defp condition_label(%{"condition" => "rows"}), do: "When there are results"
  defp condition_label(%{"condition" => "no_rows"}), do: "When there are no results"
  defp condition_label(%{"condition" => "above"} = a), do: "When above #{a["threshold"]}"
  defp condition_label(%{"condition" => "below"} = a), do: "When below #{a["threshold"]}"
  defp condition_label(_), do: "Alert"

  defp dest_label(alert) do
    emails = Alerts.parse_emails(alert["emails"])
    hooks = Alerts.parse_webhook_ids(alert["webhook_ids"])
    parts = emails ++ Enum.map(hooks, &"webhook #{&1}")
    if parts == [], do: "no destination", else: Enum.join(parts, ", ")
  end

  defp maybe_filter(questions, ""), do: questions

  defp maybe_filter(questions, q) do
    q = String.downcase(q)

    Enum.filter(questions, fn item ->
      String.contains?(String.downcase(item["name"] || ""), q)
    end)
  end

  defp run(question, socket) do
    case Query.run(question["sql"],
           database: question["database_id"],
           actor: socket.assigns.lens_actor,
           question_id: question["id"]
         ) do
      {:ok, result} -> {result, nil}
      {:error, error} -> {nil, error}
    end
  end
end
