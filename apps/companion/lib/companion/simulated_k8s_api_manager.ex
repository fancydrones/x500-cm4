defmodule Companion.SimulatedK8sApiManager do
  use GenServer

  @namespace "rpiuav"

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    deployments = get_fake_initial_deployments()

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})

    state = %{namespace: @namespace, deployments: deployments}
    {:ok, state}
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

  def handle_call(:get_configs, _from, state) do
    Logger.info("Get ConfigMap from k8s")
    result = []

      {:reply, result, state}
  end

  def handle_cast({:update_config, key, value}, state) do
    Logger.info("Updating config : key: #{key} : value: #{value}")
    {:noreply, state}
  end

  def handle_cast({:restart_deployment, deployment_name}, state) do
    Logger.info("Restart deployment: #{deployment_name}")

    {:noreply, state}
  end

  def handle_cast(:request_deployments, %{deployments: deployments} = state) do
    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})
    {:noreply, state}
  end

  defp get_fake_initial_deployments() do
    [
      %{
        name: "Companion",
        image_version: "20220801.123",
        replicas_from_spec: 1,
        ready_replicas: 1
      },
      %{
        name: "Streamer",
        image_version: "20220801.123",
        replicas_from_spec: 1,
        ready_replicas: 1
      },
      %{
        name: "Router",
        image_version: "20220801.123",
        replicas_from_spec: 1,
        ready_replicas: 1
      },
      %{
        name: "Announcer",
        image_version: "20220801.123",
        replicas_from_spec: 1,
        ready_replicas: 1
      },
    ]
  end

end
