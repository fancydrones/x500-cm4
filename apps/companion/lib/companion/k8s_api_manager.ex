defmodule Companion.K8sApiManager do
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

    {reference_deployments, deployments} = start_watch_deployments(conn, namespace)
    {reference_configs, configs} = start_watch_configs(conn, namespace)

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})
    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})

    state = %{
        connection: conn,
        namespace: namespace,
        watch_deployments_id: reference_deployments,
        watch_configs_id: reference_configs,
        deployments: deployments,
        configs: configs
      }
    {:ok, state}
  end

  defp start_watch_deployments(connection, namespace) do
    operation = K8s.Client.list("apps/v1", "Deployment", namespace: namespace)
    {resource_version, deployments} = get_deployments(connection, namespace)
    {:ok, reference} = K8s.Client.watch(connection, operation, resource_version, [stream_to: self(), recv_timeout: :infinity])
    {reference, deployments}
  end

  defp get_deployments(connection, namespace) do
    operation = K8s.Client.list("apps/v1", "Deployment", namespace: namespace)
    {:ok, deployments_result} = K8s.Client.run(connection, operation)
    resource_version = deployments_result["metadata"]["resourceVersion"]
    deployments = Enum.map(deployments_result["items"], fn deployment -> extract_deloyment_details(deployment) end)
    {resource_version, deployments}
  end

  defp extract_deloyment_details(deployment) do
    name = get_name_from_deployment(deployment)
    image_version = get_image_version_from_deployment(deployment)
    replicas_from_spec= deployment["spec"]["replicas"]

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
      ready_replicas: ready_replicas
    }
  end

  defp start_watch_configs(connection, namespace) do
    operation = K8s.Client.get("v1", :configmap, [namespace: namespace, name: @default_configmap])
    {resource_version, configs} = get_configs_from_k8s(connection, namespace)
    {:ok, reference} = K8s.Client.watch(connection, operation, resource_version, [stream_to: self(), recv_timeout: :infinity])
    {reference, configs}
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

  # WATCH: Receive update for deployments
  def handle_info(%HTTPoison.AsyncChunk{:chunk => chunk, :id => watch_id}, %{watch_deployments_id: watch_id, deployments: deployments} = state) do
    {:ok, data} = Jason.decode(chunk)
    deployment = extract_deloyment_details(data["object"])
    type = data["type"]

    deployments = update_deployments(deployment, type, deployments)

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})

    {:noreply, %{state | deployments: deployments}}
  end

  # WATCH: OK subscription for deployments
  def handle_info(%HTTPoison.AsyncStatus{:code => 200, :id => watch_id}, %{watch_deployments_id: watch_id, } = state) do
    Logger.debug("Watcher enabled OK for deployments")
    {:noreply, state}
  end

  # WATCH: Receive headers for deployments
  def handle_info(%HTTPoison.AsyncHeaders{:headers => headers, :id => watch_id}, %{watch_deployments_id: watch_id} = state) do
    Logger.debug("Watcher headers for deployments: #{Kernel.inspect(headers)}")
    {:noreply, state}
  end

  # WATCH: Subscription timed out for deployments. Will restart.
  def handle_info(%HTTPoison.AsyncEnd{:id => watch_id},%{watch_deployments_id: watch_id, connection: conn, namespace: namespace} = state) do
    Logger.debug("Watcher Ended. Will restart")
    {reference, deployments} = start_watch_deployments(conn, namespace)

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})

    state = %{state | watch_deployments_id: reference, deployments: deployments}

    {:noreply, state}
  end

  ###
  # WATCH: Receive update for configs
  def handle_info(%HTTPoison.AsyncChunk{:chunk => chunk, :id => watch_id}, %{watch_configs_id: watch_id} = state) do
    {:ok, data} = Jason.decode(chunk)
    configs = extract_configmap_details(data["object"])
    #type = data["type"]

    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})

    {:noreply, %{state | configs: configs}}
  end

  # WATCH: OK subscription for configs
  def handle_info(%HTTPoison.AsyncStatus{:code => 200, :id => watch_id}, %{watch_configs_id: watch_id, } = state) do
    Logger.debug("Watcher for configs enabled OK")
    {:noreply, state}
  end

  # WATCH: Receive headers for configs
  def handle_info(%HTTPoison.AsyncHeaders{:headers => headers, :id => watch_id}, %{watch_configs_id: watch_id} = state) do
    Logger.debug("Watcher headers for configs: #{Kernel.inspect(headers)}")
    {:noreply, state}
  end

  # WATCH: Subscription timed out for configs. Will restart.
  def handle_info(%HTTPoison.AsyncEnd{:id => watch_id},%{watch_configs_id: watch_id, connection: conn, namespace: namespace} = state) do
    Logger.debug("Watcher Ended for configs. Will restart")
    {reference, configs} = start_watch_configs(conn, namespace)

    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})

    state = %{state | watch_configs_id: reference, configs: configs}

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
