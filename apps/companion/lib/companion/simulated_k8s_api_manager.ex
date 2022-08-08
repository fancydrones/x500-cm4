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
    result = get_fake_configs()

      {:reply, result, state}
  end

  def handle_cast({:update_config, key, value}, state) do
    Logger.info("Updating config : key: #{key} : value: #{value}")
    {:noreply, state}
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

  def handle_info({:enable_deployment, deployment_name}, %{deployments: deployments} = state) do
    deployments =
      deployments
      |> Enum.map(fn d -> if d.name == deployment_name, do: %{d | ready_replicas: d.replicas_from_spec}, else: d end)

    Phoenix.PubSub.broadcast(Companion.PubSub, "deployment_updates", {:deployments, deployments})

    {:noreply, %{state | deployments: deployments}}
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
        key: "STREAMER_CAMERA_PIPELINE0",
        value: "libcamerasrc ! video/x-raw,width=1280,height=720,format=NV12,colorimetry=bt601,interlace-mode=progressive ! videoflip video-direction=180 ! videorate ! video/x-raw,framerate=30/1 ! v4l2convert ! v4l2h264enc output-io-mode=2 extra-controls=\"controls,repeat_sequence_header=1,video_bitrate_mode=1,h264_profile=3,video_bitrate=3000000\" ! video/x-h264,profile=main,level=(string)4 ! queue max-size-buffers=1 name=q_enc ! h264parse ! rtph264pay config-interval=1 name=pay0 pt=96"
      }
    ]
  end

end
