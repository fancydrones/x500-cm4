defmodule Companion.K8sManager do
  use GenServer

  @default_namespace "rpiuav"
  @default_configmap "rpi4-config"

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    {:ok, conn} = get_k8s_connection()
    namespace = get_namespace()

    operation = K8s.Client.list("apps/v1", "Deployment", namespace: namespace)
    {:ok, reference} = K8s.Client.watch(conn, operation, stream_to: self(), recv_timeout: :infinity)
    #Logger.debug(reference)

    state = %{connection: conn, namespace: namespace, watch_deployments_id: reference}
    {:ok, state}
  end

  def update_config(key, value) do
    GenServer.cast(__MODULE__, {:update_config, key, value})
  end

  def get_configs() do
    GenServer.call(__MODULE__, :get_configs)
  end

  def get_apps_details() do
    GenServer.call(__MODULE__, :get_apps_details)
  end

  def restart_deployment(deployment_name) do
    GenServer.cast(__MODULE__, {:restart_deployment, deployment_name})
  end

  def handle_call(:get_configs, _from, %{connection: conn, namespace: namespace} = state) do
    Logger.info("Get ConfigMap from k8s")
    operation = K8s.Client.get("v1", :configmap, [namespace: namespace, name: @default_configmap])
    {:ok, configmap} = K8s.Client.run(conn, operation)

    configs = configmap["data"]

    result =
      Map.keys(configs)
      |> Enum.map(fn key -> %{key: key, value: configs[key]} end)

      {:reply, result, state}
  end

  def handle_call(:get_apps_details, _from, %{connection: conn, namespace: namespace} = state) do
    Logger.info("Get Apps details from k8s")
    operation = K8s.Client.list("apps/v1", "Deployment", namespace: namespace)
    {:ok, deployments} = K8s.Client.run(conn, operation)
    result = Enum.map(deployments["items"], fn deployment -> %{tag: get_name_from_deployment(deployment), version: get_image_version_from_deployment(deployment)} end)

    {:reply, result, state}
  end

  def handle_cast({:update_config, key, value}, %{connection: conn, namespace: namespace} = state) do
    Logger.info("Updating config : key: #{key} : value: #{value}")
    body = %{data: %{key => value}}
    operation = K8s.Client.patch("v1", "configmap", [namespace: namespace, name: @default_configmap], body)
    {:ok, _configmap} = K8s.Client.run(conn, operation)
    {:noreply, state}
  end

  def handle_cast({:restart_deployment, deployment_name}, %{connection: conn, namespace: namespace} = state) do
    Logger.info("Restart deployment: #{deployment_name}")

    body = %{spec: %{template: %{metadata: %{annotations: %{"kubectl.kubernetes.io/restartedAt": DateTime.utc_now |> DateTime.to_iso8601}}}}}
    operation = K8s.Client.patch("apps/v1", "deployment", [namespace: namespace, name: deployment_name], body)

    {:ok, _deployment} = K8s.Client.run(conn, operation)
    {:noreply, state}
  end

  def handle_info(%HTTPoison.AsyncChunk{:chunk => chunk, :id => watch_id}, %{watch_deployments_id: watch_id} = state) do
    {:ok, data} = Jason.decode(chunk)

    IO.puts("**************************")
    IO.puts("Type: #{data["type"]}")
    status = data["object"]["status"]

    if Map.has_key?(status, "observedGeneration") do
      IO.puts("observedGeneration: #{status["observedGeneration"]}")
    end

    if Map.has_key?(status, "readyReplicas") do
      IO.puts("readyReplicas: #{status["readyReplicas"]}")
    end

    if Map.has_key?(status, "replicas") do
      IO.puts("replicas: #{status["replicas"]}")
    end

    if Map.has_key?(status, "updatedReplicas") do
      IO.puts("updatedReplicas: #{status["updatedReplicas"]}")
    end

    if Map.has_key?(status, "unavailableReplicas") do
      IO.puts("unavailableReplicas: #{status["unavailableReplicas"]}")
    end

    #IO.inspect(status)

    {:noreply, state}
  end

  def handle_info(%HTTPoison.AsyncStatus{:code => 200, :id => watch_id}, %{watch_deployments_id: watch_id} = state) do
    Logger.debug("Watcher enabled OK")
    {:noreply, state}
  end

  def handle_info(%HTTPoison.AsyncHeaders{:headers => headers, :id => watch_id}, %{watch_deployments_id: watch_id} = state) do
    Logger.debug("Watcher headers: #{Kernel.inspect(headers)}")
    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.warning("Receive unknown message: #{Kernel.inspect(message)}")
    {:noreply, state}
  end

  defp get_k8s_connection() do
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
