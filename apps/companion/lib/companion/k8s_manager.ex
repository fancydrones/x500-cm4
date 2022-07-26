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
    {resource_version, deployments} = get_deployments(conn, namespace)
    {:ok, reference} = K8s.Client.watch(conn, operation, resource_version, [stream_to: self(), recv_timeout: :infinity])

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})

    state = %{connection: conn, namespace: namespace, watch_deployments_id: reference, deployments: deployments}
    {:ok, state}
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

  def update_config(key, value) do
    GenServer.cast(__MODULE__, {:update_config, key, value})
  end

  def get_configs() do
    GenServer.call(__MODULE__, :get_configs)
  end

  def restart_deployment(deployment_name) do
    GenServer.cast(__MODULE__, {:restart_deployment, deployment_name})
  end

  def request_deployments() do
    GenServer.cast(__MODULE__, :request_deployments)
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

  def handle_info(%HTTPoison.AsyncChunk{:chunk => chunk, :id => watch_id}, %{watch_deployments_id: watch_id, deployments: deployments} = state) do
    {:ok, data} = Jason.decode(chunk)
    deployment = extract_deloyment_details(data["object"])
    type = data["type"]

    deployments = update_deployments(deployment, type, deployments)

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})

    {:noreply, %{state | deployments: deployments}}
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
