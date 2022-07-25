defmodule CompanionWeb.OperatorLive do

  use Phoenix.LiveView
  use Phoenix.HTML

  @default_namespace "rpiuav"
  @default_configmap "rpi4-config"

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    images = get_apps_details()
    configs = get_configs()
    socket =
      socket
      |> assign(apps: images)
      |> assign(configs: configs)
    {:ok, socket}
  end

  @impl true
  def handle_event("get_config", _, socket) do
    Logger.info("Clicked restart Get Config")

    configs = get_configs()

    socket =
      socket
      |> assign(configs: configs)

    {:noreply, socket}
  end

  def handle_event("get_versions", _, socket) do
    Logger.info("Clicked restart Get Versions")

    apps = get_apps_details()

    socket =
      socket
      |> assign(apps: apps)

    {:noreply, socket}
  end

  def handle_event("restart_router", _, socket) do
    Logger.info("Clicked restart Router")

    restart_deployment("router")

    {:noreply, socket}
  end

  def handle_event("restart_streamer", _, socket) do
    Logger.info("Clicked restart Streamer")

    restart_deployment("streamer")

    {:noreply, socket}
  end

  def handle_event("restart_announcer", _, socket) do
    Logger.info("Clicked restart Announcer")

    restart_deployment("announcer")

    {:noreply, socket}
  end

  def handle_event("restart_companion", _, socket) do
    Logger.info("Clicked restart Companion")

    restart_deployment("companion")

    {:noreply, socket}
  end

  def handle_event("save_config", %{"config" => update}, socket) do
    {key, value} =
      update
      |> Map.to_list
      |> List.first

    Logger.info("Key: #{key} -- Value: #{value}")

    update_config(key, value)
    {:noreply, socket}
  end

  def update_config(key, value) do
    Logger.info("Updating config using new method")
    {:ok, conn} = get_k8s_connection()
    namespace = get_namespace()

    body = %{data: %{key => value}}
    operation = K8s.Client.patch("v1", "configmap", [namespace: namespace, name: @default_configmap], body)

    {:ok, _configmap} = K8s.Client.run(conn, operation)
  end


  def get_k8s_connection() do
    case Application.get_env(:companion, :use_file, :false) do
      :true -> K8s.Conn.from_file(Application.get_env(:companion, :file_path))
      _ -> K8s.Conn.from_service_account()
    end
  end

  defp get_namespace() do
    case Application.get_env(:companion, :namespace_file, :NOTSET) do
      :NOTSET ->
        Logger.debug("Using default namespace: #{@default_namespace}")
        @default_namespace
      namespace_file ->
        Logger.debug("Getting namespace using file: #{namespace_file}")
        {:ok, namespace} = File.read(namespace_file)
        namespace |> String.trim |> IO.inspect
    end
  end

  def restart_deployment(deployment_name) do
    Logger.info("Restart using new method")
    {:ok, conn} = get_k8s_connection()
    namespace = get_namespace()

    body = %{spec: %{template: %{metadata: %{annotations: %{"kubectl.kubernetes.io/restartedAt": DateTime.utc_now |> DateTime.to_iso8601}}}}}
    operation = K8s.Client.patch("apps/v1", "deployment", [namespace: namespace, name: deployment_name], body)

    {:ok, _deployment} = K8s.Client.run(conn, operation)
  end

  def get_configs() do
    Logger.info("Get Apps details using new method")
    {:ok, conn} = get_k8s_connection()
    namespace = get_namespace()

    operation = K8s.Client.get("v1", :configmap, [namespace: namespace, name: @default_configmap])
    {:ok, configmap} = K8s.Client.run(conn, operation)

    configs = configmap["data"]

    Map.keys(configs)
    |> Enum.map(fn key -> %{key: key, value: configs[key]} end)
  end

  def get_apps_details() do
    Logger.info("Get Apps details using new method")
    {:ok, conn} = get_k8s_connection()
    namespace = get_namespace()
    operation = K8s.Client.list("apps/v1", "Deployment", namespace: namespace)
    {:ok, deployments} = K8s.Client.run(conn, operation)
    Enum.map(deployments["items"], fn deployment -> %{tag: get_name_from_deployment(deployment), version: get_image_version_from_deployment(deployment)} end)
  end

  defp get_name_from_deployment(deployment) do
    deployment["metadata"]["name"]
  end

  defp get_image_version_from_deployment(deployment) do
    containers = deployment["spec"]["template"]["spec"]["containers"]
    c = List.first(containers)
    tag = c["image"]
    [_image, version] = String.split(tag, ":")
    version
  end
end
