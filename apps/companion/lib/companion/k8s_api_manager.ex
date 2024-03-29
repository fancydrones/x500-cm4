defmodule Companion.K8sApiManager do
  use GenServer

  @default_namespace "rpiuav"
  @default_configmap "rpi4-config"
  @metrics_interval 60000

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    {:ok, conn} = get_k8s_connection()

    # TODO: Make configurable
    conn = struct!(conn, insecure_skip_tls_verify: true)

    Logger.debug("K8s connection: #{inspect(conn)}")

    namespace = get_namespace()

    {reference_deployments, deployments} = start_watch_deployments(conn, namespace)
    {reference_configs, configs} = start_watch_configs(conn, namespace)

    node_metrics = start_simple_watch_node_metrics(conn)
    pod_metrics = start_simple_watch_pod_metrics(conn, namespace)

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})
    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})

    state = %{
        connection: conn,
        namespace: namespace,
        watch_deployments_id: reference_deployments,
        watch_configs_id: reference_configs,
        deployments: deployments,
        configs: configs,
        node_metrics: node_metrics,
        pod_metrics: pod_metrics
      }
    {:ok, state}
  end

  defp start_watch_deployments(connection, namespace) do
    #operation = K8s.Client.list("apps/v1", "Deployment", namespace: namespace)
    {resource_version, deployments} = get_deployments(connection, namespace)
    Logger.debug("Resource version: #{resource_version}")
    Logger.debug("Deployments: #{inspect(deployments)}")

    Logger.debug("Starting watch for deployments")
    path_params = [namespace: namespace, name: @default_configmap, sendInitialEvents: "true", resourceVersion: resource_version, resourceVersionMatch: "NotOlderThan"]

    operation = K8s.Client.watch("apps/v1", "Deployment", path_params)

    parent_process = self()
    {:ok, pid} = Task.Supervisor.start_link()
    deployment_task = Task.Supervisor.async(pid, fn ->
      {:ok, stream_events} = K8s.Client.Runner.Stream.Watch.stream(connection, operation, path_params)

      stream_events
      |> Stream.map(fn message -> send(parent_process, {:deployments_watch, message}) end)
      |> Stream.run()
    end)

    {deployment_task, deployments}
  end

  defp get_deployments(connection, namespace) do
    operation = K8s.Client.list("apps/v1", "Deployment", namespace: namespace)
    {:ok, deployments_result} = K8s.Client.run(connection, operation)
    resource_version = deployments_result["metadata"]["resourceVersion"]
    deployments = Enum.map(deployments_result["items"], fn deployment -> extract_deloyment_details(deployment) end)
    {resource_version, deployments}
  end

  defp start_simple_watch_node_metrics(connection) do
    Process.send_after(self(), {:publish_node_metrics}, 2000)
    get_node_metrics(connection)
  end

  defp start_simple_watch_pod_metrics(connection, namespace) do
    Process.send_after(self(), {:publish_pod_metrics}, 2000)
    get_pod_metrics(connection, namespace)
  end

  defp get_node_metrics(connection) do
    operation = K8s.Client.list("metrics.k8s.io/v1beta1", "nodes")

    {:ok, node_metrics_result} = K8s.Client.run(connection, operation)
    Enum.map(node_metrics_result["items"], fn node_metric -> extract_node_metric_details(node_metric) end)
  end

  defp get_pod_metrics(connection, namespace) do
    operation = K8s.Client.list("metrics.k8s.io/v1beta1", "pods", [namespace: namespace])

    {:ok, pod_metrics_result} = K8s.Client.run(connection, operation)
    Enum.map(pod_metrics_result["items"], fn pod_metric -> extract_pod_metric_details(pod_metric) end)
  end

  defp extract_deloyment_details(deployment) do
    name = get_name_from_deployment(deployment)
    image_version = get_image_version_from_deployment(deployment)
    replicas_from_spec= deployment["spec"]["replicas"]
    selector = deployment["spec"]["selector"]["matchLabels"]

    status = deployment["status"]
    ready_replicas =
      case is_map(status) and Map.has_key?(status, "readyReplicas") do
        true -> status["readyReplicas"]
        _ -> 0
      end
    %{
      name: name,
      image_version: image_version,
      replicas_from_spec: replicas_from_spec,
      ready_replicas: ready_replicas,
      selector: selector
    }
  end

  defp extract_node_metric_details(node_metrics) do
    name = node_metrics["metadata"]["name"]
    timestamp = node_metrics["timestamp"]
    cpu = node_metrics["usage"]["cpu"]
    memory = node_metrics["usage"]["memory"]
    %{
      name: name,
      timestamp: timestamp,
      cpu: cpu,
      memory: memory
    }
  end

  defp extract_pod_metric_details(pod_metrics) do
    name = pod_metrics["metadata"]["name"]
    namespace = pod_metrics["metadata"]["namespace"]
    timestamp = pod_metrics["timestamp"]
    containers = extract_all_container_metrics_for_pod(pod_metrics)
    labels = pod_metrics["metadata"]["labels"]

    %{
      name: name,
      namespace: namespace,
      timestamp: timestamp,
      containers: containers,
      labels: labels
    }
  end

  defp extract_all_container_metrics_for_pod(pod_metrics) do
    pod_metrics["containers"]
    |> Enum.map(fn container -> extract_container_metric_details(container) end)
  end

  defp extract_container_metric_details(container) do
    name = container["name"]
    cpu = container["usage"]["cpu"]
    memory = container["usage"]["memory"]
    %{
      name: name,
      cpu: cpu,
      memory: memory
    }
  end

  defp start_watch_configs(connection, namespace) do
    {resource_version, configs} = get_configs_from_k8s(connection, namespace)
    Logger.debug("Resource version: #{resource_version}")
    Logger.debug("Configs: #{inspect(configs)}")

    Logger.debug("Starting watch for configmap")
    path_params = [namespace: namespace, name: @default_configmap, sendInitialEvents: "true", resourceVersion: resource_version, resourceVersionMatch: "NotOlderThan"]

    operation = K8s.Client.watch("v1", :configmap, path_params)

    parent_process = self()
    {:ok, pid} = Task.Supervisor.start_link()
    watch_task = Task.Supervisor.async(pid, fn ->
      {:ok, stream_events} = K8s.Client.Runner.Stream.Watch.stream(connection, operation, path_params)

      stream_events
      |> Stream.map(fn message -> send(parent_process, {:configmap_watch, message}) end)
      |> Stream.run()
    end)

    {watch_task, configs}
  end

  defp get_configs_from_k8s(connection, namespace) do

    configmap_name = @default_configmap

    # Needs to use LIST to get updated resource version, and filter result from list.
    # GET would be more precise, but return outdated resource version
    operation = K8s.Client.list("v1", :configmap, [namespace: namespace])
    {:ok, configmaps_result} = K8s.Client.run(connection, operation)
    configmaps =
      configmaps_result["items"]
      |> Enum.filter(fn configmap -> configmap["metadata"]["name"] == configmap_name end)
      |> Enum.map(fn configmap -> extract_configmap_details(configmap) end)
    resource_version = configmaps_result["metadata"]["resourceVersion"]

    result = List.first(configmaps)
    {resource_version, result}
  end

  defp extract_configmap_details(configmap) do
    configs = configmap["data"]

    configs
    |> Map.keys()
    |> Enum.map(fn key -> %{key: key, value: configs[key]} end)
  end

  def update_config(key, value) do
    GenServer.cast(__MODULE__, {:update_config, key, value})
  end

  def restart_deployment(deployment_name) do
    GenServer.cast(__MODULE__, {:restart_deployment, deployment_name})
  end

  def request_deployments() do
    GenServer.cast(__MODULE__, :request_deployments)
  end

  def request_configs() do
    GenServer.cast(__MODULE__, :request_configs)
  end

  def request_node_metrics() do
    GenServer.cast(__MODULE__, :request_node_metrics)
  end

  def request_pod_metrics() do
    GenServer.cast(__MODULE__, :request_pod_metrics)
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

  def handle_cast(:request_deployments, %{deployments: deployments} = state) do
    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})
    {:noreply, state}
  end

  def handle_cast(:request_configs, %{configs: configs} = state) do
    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})
    {:noreply, state}
  end

  def handle_cast(:request_node_metrics, %{node_metrics: node_metrics} = state) do
    Phoenix.PubSub.broadcast(Companion.PubSub, "node_metrics_updates", {:node_metrics, node_metrics})
    {:noreply, state}
  end

  def handle_cast(:request_pod_metrics, %{pod_metrics: pod_metrics} = state) do
    Phoenix.PubSub.broadcast(Companion.PubSub, "pod_metrics_updates", {:pod_metrics, pod_metrics})
    {:noreply, state}
  end

  def handle_info({:configmap_watch, %{"type" => "MODIFIED", "object" => object} = message}, state) do
    Logger.debug("Received configmap watch message: #{inspect(message)}")
    configs = extract_configmap_details(object)
    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})
    {:noreply, %{state | configs: configs}}
  end

  def handle_info({:configmap_watch, message}, state) do
    Logger.warning("Received unknown configmap watch message: #{inspect(message)}")
    {:noreply, state}
  end

  def handle_info({:deployments_watch, message}, %{deployments: deployments} = state) do
    Logger.warning("Received deployments watch message: #{inspect(message)}")
    deployment = extract_deloyment_details(message["object"])
    type = message["type"]
    deployments = update_deployments(deployment, type, deployments)
    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})
    {:noreply, %{state | deployments: deployments}}
  end

  def handle_info({:publish_node_metrics}, %{connection: conn} = state) do
    node_metrics = get_node_metrics(conn)
    Phoenix.PubSub.broadcast(Companion.PubSub, "node_metrics_updates", {:node_metrics, node_metrics})
    Process.send_after(self(), {:publish_node_metrics}, @metrics_interval)
    {:noreply, state}
  end

  def handle_info({:publish_pod_metrics}, %{connection: conn, namespace: namespace} = state) do
    pod_metrics = get_pod_metrics(conn, namespace)
    Phoenix.PubSub.broadcast(Companion.PubSub, "pod_metrics_updates", {:pod_metrics, pod_metrics})
    Process.send_after(self(), {:publish_pod_metrics}, @metrics_interval)
    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.warning("Receive unknown message: #{Kernel.inspect(message)}")
    {:noreply, state}
  end

  defp update_deployments(deployment, "ADDED", deployments) do
    Logger.debug("ADD: #{deployment.name}")
    deployments ++ [deployment]
  end

  defp update_deployments(deployment, "DELETED", deployments) do
    Logger.debug("DEL: #{deployment.name}")
    Enum.filter(deployments, fn d -> d.name != deployment.name end)
  end

  defp update_deployments(deployment, "MODIFIED", deployments) do
    Logger.debug("MOD: #{deployment.name}")
    Enum.map(deployments, fn d ->
          case d.name == deployment.name do
            true -> deployment
            _ -> d
          end
        end)
  end

  defp update_deployments(deployment, "ERROR", deployments) do
    Logger.error("Watcher failed: #{Kernel.inspect(deployment)}")
    deployments
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
    if containers != :nil do
      c = List.first(containers)
      tag = c["image"]
      [_image, version] = String.split(tag, ":")
      version
    else
      "UNKNOWN"
    end
  end
end
