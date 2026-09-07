defmodule PhoenixLens.Alerts.Scheduler do
  @moduledoc false
  use GenServer

  @tick_ms 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    _ = safe_run()
    schedule()
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp schedule, do: Process.send_after(self(), :tick, @tick_ms)

  defp safe_run do
    PhoenixLens.Alerts.Runner.run_due()
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end
end
