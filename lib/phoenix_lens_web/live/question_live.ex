defmodule PhoenixLensWeb.QuestionLive do
  @moduledoc false
  use PhoenixLensWeb, :live_view

  alias PhoenixLens.{Autocomplete, Dashboards, Questions, Query}

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
         |> assign(:dashboards, Dashboards.list())}

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
  def handle_event("run", _params, socket) do
    q = Map.put(socket.assigns.question, "sql", socket.assigns.sql)
    {result, error} = run(q, socket)
    {:noreply, socket |> assign(:result, result) |> assign(:error, error)}
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
        />
        <div class="lens-question-actions">
          <button type="button" class="ghost" phx-click="toggle-editor">
            {if @editor_open, do: "Hide editor", else: "Show editor"}
          </button>
          <a class="ghost btn-link" href={"#{@lens_prefix}/questions/#{@question["id"]}/csv"}>CSV</a>
          <button type="button" class="ghost" phx-click="delete" data-confirm="Delete this question?">
            Delete
          </button>
          <button type="submit" form="q-form">Save</button>
        </div>
      </header>

      <form id="q-form" phx-submit="save" phx-change="change" class="lens-ask">
        <div class="lens-filter-row">
          <button type="button" class="ghost" phx-click="run">Refresh</button>
        </div>
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
    </div>
    """
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
