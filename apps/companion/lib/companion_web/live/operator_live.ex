defmodule CompanionWeb.OperatorLive do
  use Phoenix.LiveView
  use Phoenix.HTML

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    images = Companion.K8sManager.get_apps_details()
    configs = Companion.K8sManager.get_configs()
    socket =
      socket
      |> assign(apps: images)
      |> assign(configs: configs)
    {:ok, socket}
  end

  @impl true
  def handle_event("get_config", _, socket) do
    Logger.info("Clicked restart Get Config")

    configs = Companion.K8sManager.get_configs()

    socket =
      socket
      |> assign(configs: configs)

    {:noreply, socket}
  end

  def handle_event("get_versions", _, socket) do
    Logger.info("Clicked restart Get Versions")

    apps = Companion.K8sManager.get_apps_details()

    socket =
      socket
      |> assign(apps: apps)

    {:noreply, socket}
  end

  def handle_event("restart_router", _, socket) do
    Logger.info("Clicked restart Router")

    Companion.K8sManager.restart_deployment("router")

    {:noreply, socket}
  end

  def handle_event("restart_streamer", _, socket) do
    Logger.info("Clicked restart Streamer")

    Companion.K8sManager.restart_deployment("streamer")

    {:noreply, socket}
  end

  def handle_event("restart_announcer", _, socket) do
    Logger.info("Clicked restart Announcer")

    Companion.K8sManager.restart_deployment("announcer")

    {:noreply, socket}
  end

  def handle_event("restart_companion", _, socket) do
    Logger.info("Clicked restart Companion")

    Companion.K8sManager.restart_deployment("companion")

    {:noreply, socket}
  end

  def handle_event("save_config", %{"config" => update}, socket) do
    {key, value} =
      update
      |> Map.to_list
      |> List.first

    Logger.info("Key: #{key} -- Value: #{value}")

    Companion.K8sManager.update_config(key, value)
    {:noreply, socket}
  end
end
