defmodule CompanionWeb.OperatorLive do
  use Phoenix.LiveView
  use Phoenix.HTML

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    configs = Companion.K8sManager.get_configs()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Companion.PubSub, "deployment_updates")
      Companion.K8sManager.request_deployments()
    end

    socket =
      socket
      |> assign(deployments: [])
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

  @impl true
  def handle_info({:deployments, deployments}, socket) do
    Logger.debug("Web got updated deployments")
    socket =
      socket
      |> assign(deployments: convert_deployments(deployments))
    {:noreply, socket}
  end

  defp convert_deployments(deployments) do
    Enum.map(deployments, fn d -> %{
          name: d.name,
          image_version: d.image_version,
          replicas_from_spec: d.replicas_from_spec,
          ready_replicas: d.ready_replicas,
          backgrond_color: get_color_from_count(d.ready_replicas, d.replicas_from_spec)
        }
      end)
  end

  defp get_color_from_count(ready_replicat, expected_replicas) do
    if ready_replicat < expected_replicas do
      "background-color: red;"
    else
      "background-color: green;"
    end
  end

end
