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
  @stream_status_interval 2000

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
      boot_time: System.monotonic_time(:millisecond),
      enable_stream_status: Config.enable_stream_status!()
    }

    Logger.info(
      "Camera initialized: #{state.camera_name} (ID: #{state.camera_id}) on system #{state.system_id}"
    )

    # Subscribe to COMMAND_LONG messages
    # as_frame: true ensures we receive the frame with source_system/component info
    # We subscribe to ALL CommandLong messages and filter them in handle_info
    Router.subscribe(message: Common.Message.CommandLong, as_frame: true)

    Logger.info("Subscribed to CommandLong messages. Waiting for commands from QGC...")

    # Start heartbeat timer
    schedule_heartbeat()

    # Optionally start periodic stream status announcements
    if state.enable_stream_status do
      schedule_stream_status()
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:send_heartbeat, state) do
    heartbeat = MessageBuilder.build_heartbeat()
    Router.pack_and_send(heartbeat)

    Logger.debug("Sent heartbeat: type=#{inspect(heartbeat.type)}, autopilot=#{inspect(heartbeat.autopilot)}, system_status=#{inspect(heartbeat.system_status)}")

    schedule_heartbeat()
    {:noreply, state}
  end

  @impl true
  def handle_info(:send_stream_status, state) do
    status = MessageBuilder.build_video_stream_status(state)
    Router.pack_and_send(status)

    Logger.debug("Sent stream status")

    schedule_stream_status()
    {:noreply, state}
  end

  @impl true
  def handle_info(frame = %XMAVLink.Frame{message: command_msg}, state)
      when is_struct(command_msg, Common.Message.CommandLong) do
    # Check if command is for this component
    # Accept commands targeted at:
    # 1. This specific component (target_system == our system AND target_component == our component)
    # 2. Broadcast to all components on our system (target_system == our system AND target_component == 0)
    # 3. Broadcast to all systems (target_system == 0)
    target_matches =
      (command_msg.target_system == 0) or
        (command_msg.target_system == state.system_id and
           (command_msg.target_component == 0 or command_msg.target_component == state.camera_id))

    if target_matches do
      Logger.info(
        "Processing command #{command_msg.command} from #{frame.source_system}/#{frame.source_component} " <>
          "for target #{command_msg.target_system}/#{command_msg.target_component} " <>
          "(we are #{state.system_id}/#{state.camera_id})"
      )

      CommandHandler.handle_command(command_msg, frame, state)
    else
      Logger.debug(
        "Ignoring command for system #{command_msg.target_system}/#{command_msg.target_component} " <>
          "(we are #{state.system_id}/#{state.camera_id})"
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    # Log the type of message received for debugging
    case msg do
      %XMAVLink.Frame{message: message} ->
        message_type = message.__struct__ |> Module.split() |> List.last()
        Logger.debug("Received non-command message: #{message_type}")

      _ ->
        Logger.debug("Received unknown message: #{inspect(msg)}")
    end

    {:noreply, state}
  end

  # Private Functions

  defp schedule_heartbeat do
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
  end

  defp schedule_stream_status do
    Process.send_after(self(), :send_stream_status, @stream_status_interval)
  end
end
