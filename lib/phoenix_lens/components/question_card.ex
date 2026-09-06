defmodule PhoenixLens.Components.QuestionCard do
  @moduledoc """
  Embed a saved question in a host LiveView.

      <.live_component
        module={PhoenixLens.Components.QuestionCard}
        id={"q-\#{id}"}
        question_id={id}
      />
  """

  use Phoenix.LiveComponent

  alias PhoenixLens.{Policy, Questions, Query, Result}

  def update(assigns, socket) do
    actor = assigns[:actor] || "anonymous"
    question_id = assigns.question_id

    socket =
      socket
      |> assign(assigns)
      |> assign(:actor, actor)
      |> load(question_id, actor)

    {:ok, socket}
  end

  defp load(socket, question_id, actor) do
    case Questions.get(question_id) do
      {:ok, question} ->
        {result, error} =
          case Query.run(question["sql"],
                 database: question["database_id"],
                 actor: actor,
                 question_id: question["id"]
               ) do
            {:ok, result} -> {result, nil}
            {:error, error} -> {nil, error}
          end

        socket
        |> assign(:question, question)
        |> assign(:result, result)
        |> assign(:error, error)

      {:error, error} ->
        socket
        |> assign(:question, nil)
        |> assign(:result, nil)
        |> assign(:error, error)
    end
  end

  def render(assigns) do
    ~H"""
    <div class="phoenix-lens-card">
      <h3>{@question && @question["name"]}</h3>
      <%= if @error do %>
        <p class="phoenix-lens-error">{@error.message}</p>
      <% else %>
        <PhoenixLensWeb.Components.ResultTable.result_table result={@result} />
      <% end %>
    </div>
    """
  end

  def masked?(result, column) do
    result && column in result.masked_columns
  end

  def cell(value), do: Result.display_cell(value)

  def protected_fields do
    Policy.protected_set(PhoenixLens.Config.get())
  end
end
