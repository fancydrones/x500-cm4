defmodule Companion.SimulatedK8sApiManager do
  use GenServer

  @namespace "rpiuav"
  @metrics_interval 5000

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    deployments = get_fake_initial_deployments()
    configs = get_fake_configs()
    node_metrics = get_fake_node_metrics()
    pod_metrics = get_fake_pod_metrics()

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})
    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})

    start_simple_watch_node_metrics()
    start_simple_watch_pod_metrics()

    state = %{namespace: @namespace, deployments: deployments, configs: configs, node_metrics: node_metrics, pod_metrics: pod_metrics}
    {:ok, state}
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

  defp start_simple_watch_node_metrics() do
    Process.send_after(self(), {:publish_node_metrics}, 1000)
  end

  defp start_simple_watch_pod_metrics() do
    Process.send_after(self(), {:publish_pod_metrics}, 2000)
  end

  def handle_cast({:update_config, key, value}, %{configs: configs} = state) do
    Logger.info("Updating config : key: #{key} : value: #{value}")

    configs =
      configs
      |> Enum.map(fn c -> if c.key == key, do: %{c | value: value}, else: c end)

    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})

    {:noreply, %{state | configs: configs}}
  end

  def handle_cast({:restart_deployment, deployment_name}, %{deployments: deployments} = state) do
    Logger.info("Restart deployment: #{deployment_name}")

    deployments =
      deployments
      |> Enum.map(fn d -> if d.name == deployment_name, do: %{d | ready_replicas: 0}, else: d end)

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})

    Process.send_after(self(), {:enable_deployment, deployment_name}, 3000)
    {:noreply, %{state | deployments: deployments}}
  end

  def handle_cast(:request_deployments, %{deployments: deployments} = state) do
    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})
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

  def handle_cast(:request_configs, %{configs: configs} = state) do
    Phoenix.PubSub.broadcast(Companion.PubSub, "config_updates", {:configs, configs})
    {:noreply, state}
  end

  def handle_info({:enable_deployment, deployment_name}, %{deployments: deployments} = state) do
    deployments =
      deployments
      |> Enum.map(fn d -> if d.name == deployment_name, do: %{d | ready_replicas: d.replicas_from_spec}, else: d end)

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})

    {:noreply, %{state | deployments: deployments}}
  end

  def handle_info({:publish_node_metrics}, state) do
    node_metrics = get_fake_node_metrics()

    Phoenix.PubSub.broadcast(Companion.PubSub, "node_metrics_updates", {:node_metrics, node_metrics})

    Process.send_after(self(), {:publish_node_metrics}, @metrics_interval)

    {:noreply, state}
  end

  def handle_info({:publish_pod_metrics}, state) do
    pod_metrics = get_fake_pod_metrics()

    Phoenix.PubSub.broadcast(Companion.PubSub, "pod_metrics_updates", {:pod_metrics, pod_metrics})

    Process.send_after(self(), {:publish_pod_metrics}, @metrics_interval)

    {:noreply, state}
  end

  defp get_fake_node_metrics() do
    [
      %{
        cpu: "696272799n",
        memory: "1242600Ki",
        name: "rpiuav",
        timestamp: "2022-12-31T10:53:39Z"
      }
    ]
  end

  defp get_fake_pod_metrics() do
    [
      %{
        containers: [
          %{cpu: "6104966n", memory: "27796Ki", name: "announcer"}
        ],
        name: "announcer-86bbdb5777-rdxrl",
        namespace: "rpiuav",
        timestamp: "2022-12-31T10:53:39Z"
      },
      %{
        containers: [
          %{cpu: "2270820n", memory: "98132Ki", name: "companion"}
        ],
        name: "companion-7898757d4c-tfrff",
        namespace: "rpiuav",
        timestamp: "2022-12-31T10:53:38Z"
      },
      %{
        containers: [
          %{cpu: "12261355n", memory: "620Ki", name: "router"}
        ],
        name: "router-6bf49fbc67-92w7s",
        namespace: "rpiuav", timestamp: "2022-12-31T10:53:41Z"
      },
      %{
        containers: [
          %{cpu: "147128484n", memory: "15208Ki", name: "streamer"}
        ],
        name: "streamer-7db957864f-bqlnf",
        namespace: "rpiuav",
        timestamp: "2022-12-31T10:53:40Z"
      }
    ]
  end

  defp get_fake_initial_deployments() do
    [
      %{
        name: "companion",
        image_version: "20220801.123",
        replicas_from_spec: 1,
        ready_replicas: 1
      },
      %{
        name: "streamer",
        image_version: "20220801.123",
        replicas_from_spec: 1,
        ready_replicas: 1
      },
      %{
        name: "router",
        image_version: "20220801.123",
        replicas_from_spec: 1,
        ready_replicas: 1
      },
      %{
        name: "announcer",
        image_version: "20220801.123",
        replicas_from_spec: 1,
        ready_replicas: 1
      },
    ]
  end

  defp get_fake_configs() do
    [
      %{
        key: "ANNOUNCER_CAMERA_URL",
        value: "rtsp://10.10.10.2:8554/video0"
      },
      %{
        key: "ANNOUNCER_SYSTEM_ID",
        value: "1"
      },
      %{
        key: "ROUTER_CONFIG",
        value: """
            [General]
            #Mavlink-router serves on this TCP port
            TcpServerPort=5760
            ReportStats=false
            MavlinkDialect=auto

            [UartEndpoint FlightControllerSerial]
            Device = /dev/serial0
            Baud = 921600

            [UdpEndpoint FlightControllerUDP]
            Mode = Eavesdropping
            Address = 0.0.0.0
            Port = 14555

            [UdpEndpoint video0]
            Mode = Server
            Address = 0.0.0.0
            Port = 14560
            AllowMsgIdOut = 0,4,76,322,323

            [UdpEndpoint video1]
            Mode = server
            Address = 0.0.0.0
            Port = 14561
            AllowMsgIdOut = 0,4,76,322,323

            [UdpEndpoint GCS]
            Mode = Normal
            Address = 10.10.10.70
            Port = 14550

            [UdpEndpoint HAL]
            Mode = Normal
            Address = 10.10.10.99
            Port = 14550

            [UdpEndpoint DELL]
            Mode = Normal
            Address = 10.10.10.98
            Port = 14550
            """
      },
      %{
        key: "STREAMER_CONFIG",
        value: """
                paths:
                  cam:
                    source: rpiCamera
                    rpiCameraWidth: 1280
                    rpiCameraHeight: 720
                    rpiCameraVFlip: true
                    rpiCameraHFlip: true
                """
      }
    ]
  end

end
