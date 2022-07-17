defmodule CompanionWeb.OperatorLive do
  use Phoenix.LiveView

  require Logger

  def mount(_session, socket) do
    {:ok, socket}
  end

  def handle_event("restart_router", _, socket) do
    Logger.info("Clicked restart Router")
    #DroneAction.action(:gear_up_button)
    {:noreply, socket}
  end

  def handle_event("restart_streamer", _, socket) do
    Logger.info("Clicked restart Streamer")
    #DroneAction.action(:gear_down_button)
    {:noreply, socket}
  end

  def handle_event("restart_announcer", _, socket) do
    Logger.info("Clicked restart Announcer")
    #DroneAction.action(:shutdown_button)
    {:noreply, socket}
  end

  def render(assigns) do
    ~L"""
    <div id="liveoperator_landinggear_container">
      <h1>Restart apps:</h1>
      <button phx-click="restart_router">Router</button>
      <button phx-click="restart_streamer">Streamer</button>
      <button phx-click="restart_announcer">Announcer</button>
    </div>
    """
  end
end
