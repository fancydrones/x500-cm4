defmodule AnnouncerEx.CameraManager do
  @moduledoc """
  GenServer that manages the camera component lifecycle.
  - Sends heartbeats every second
  - Subscribes to and handles MAVLink COMMAND_LONG messages
  - Maintains camera state
  """

  use GenServer

  alias AnnouncerEx.{CommandHandler, Config, MessageBuilder}
  alias XMAVLink.Router

  require Logger

  @heartbeat_interval 1000
  @camera_info_interval 5000

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting CameraManager")

    # Load configuration
    state = %{
      camera_id: Config.camera_id!(),
      camera_name: Config.camera_name!(),
      stream_url: Config.camera_url!(),
      system_id: Config.system_id!(),
      boot_time: System.monotonic_time(:millisecond)
    }

    Logger.info(
      "Camera initialized: #{state.camera_name} (ID: #{state.camera_id}) on system #{state.system_id}"
    )

    # Subscribe to COMMAND_LONG messages for this component
    # as_frame: true ensures we receive the frame with source_system/component info
    Router.subscribe(message: Common.Message.CommandLong, as_frame: true)

    # Start heartbeat timer
    schedule_heartbeat()

    # Start periodic camera information announcements
    schedule_camera_info()

    {:ok, state}
  end

  @impl true
  def handle_info(:send_heartbeat, state) do
    heartbeat = MessageBuilder.build_heartbeat()
    Router.pack_and_send(heartbeat)

    Logger.debug("Sent heartbeat")

    schedule_heartbeat()
    {:noreply, state}
  end

  @impl true
  def handle_info(:send_camera_info, state) do
    # Send camera information
    camera_info = MessageBuilder.build_camera_information(state)
    Router.pack_and_send(camera_info)

    # Send video stream information
    stream_info = MessageBuilder.build_video_stream_information(state)
    Router.pack_and_send(stream_info)

    Logger.debug("Sent camera information and stream details")

    schedule_camera_info()
    {:noreply, state}
  end

  @impl true
  def handle_info(frame = %XMAVLink.Frame{message: command_msg}, state)
      when is_struct(command_msg, Common.Message.CommandLong) do
    # Check if command is for this component
    if command_msg.target_system == state.system_id and
         command_msg.target_component == state.camera_id do
      Logger.debug(
        "Processing command #{command_msg.command} from #{frame.source_system}/#{frame.source_component} for system #{state.system_id}/#{state.camera_id}"
      )

      CommandHandler.handle_command(command_msg, frame, state)
    else
      Logger.debug(
        "Ignoring command for system #{command_msg.target_system}/#{command_msg.target_component}"
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp schedule_heartbeat do
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
  end

  defp schedule_camera_info do
    Process.send_after(self(), :send_camera_info, @camera_info_interval)
  end
end
