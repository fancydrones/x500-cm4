defmodule AnnouncerEx.CommandHandler do
  @moduledoc """
  Handles MAVLink camera commands.
  """

  alias AnnouncerEx.MessageBuilder
  alias XMAVLink.Router

  require Logger

  # MAVLink command IDs
  @mav_cmd_request_message 512
  @mav_cmd_request_camera_information 521
  @mav_cmd_request_video_stream_information 2504
  @mav_cmd_request_camera_settings 522
  @mav_cmd_request_video_stream_status 2505
  @mav_cmd_request_camera_capture_status 527
  @mav_cmd_request_storage_information 525
  @mav_cmd_set_camera_zoom 531

  # MAVLink message IDs for REQUEST_MESSAGE
  @msg_id_camera_information 259
  @msg_id_video_stream_information 269
  @msg_id_video_stream_status 270

  @doc """
  Handles a command from a COMMAND_LONG message.
  
  ## Parameters
    - `command_msg`: The COMMAND_LONG message containing the command to handle.
    - `frame`: The MAVLink frame containing metadata about the message, including
      `source_system` and `source_component`, which identify the origin of the command.
      These are extracted to determine where to send responses and for logging.
    - `state`: The current state of the system.
  """
  def handle_command(command_msg, frame, state) do
    command_id = command_msg.command
    # Extract the actual source from the frame header
    source_system = frame.source_system
    source_component = frame.source_component

    Logger.debug("Received command: #{command_id} from #{source_system}/#{source_component}")

    case command_id do
      @mav_cmd_request_message ->
        requested_msg_id = trunc(command_msg.param1)
        handle_request_message(requested_msg_id, command_msg, source_system, source_component, state)

      @mav_cmd_request_camera_information ->
        handle_request_camera_information(command_msg, source_system, source_component, state)

      @mav_cmd_request_video_stream_information ->
        handle_request_video_stream_information(
          command_msg,
          source_system,
          source_component,
          state
        )

      @mav_cmd_request_camera_settings ->
        handle_request_camera_settings(command_msg, source_system, source_component, state)

      @mav_cmd_request_video_stream_status ->
        handle_request_video_stream_status(command_msg, source_system, source_component, state)

      @mav_cmd_request_camera_capture_status ->
        handle_request_capture_status(command_msg, source_system, source_component, state)

      @mav_cmd_request_storage_information ->
        handle_request_storage_information(command_msg, source_system, source_component, state)

      @mav_cmd_set_camera_zoom ->
        handle_set_camera_zoom(command_msg, source_system, source_component, state)

      _ ->
        Logger.debug("Ignoring unknown command: #{command_id}")
        :ok
    end
  end

  # Handle MAV_CMD_REQUEST_MESSAGE command
  defp handle_request_message(msg_id, command_msg, source_system, source_component, state) do
    Logger.debug("Request for message ID: #{msg_id}")

    case msg_id do
      @msg_id_camera_information ->
        send_ack(command_msg, :mav_result_accepted, source_system, source_component)
        camera_info = MessageBuilder.build_camera_information(state)
        Router.pack_and_send(camera_info)

      @msg_id_video_stream_information ->
        send_ack(command_msg, :mav_result_accepted, source_system, source_component)
        # Send all stream information messages
        stream_infos = MessageBuilder.build_all_stream_info(state)
        Enum.each(stream_infos, &Router.pack_and_send/1)

      @msg_id_video_stream_status ->
        send_ack(command_msg, :mav_result_accepted, source_system, source_component)
        status = MessageBuilder.build_video_stream_status(state)
        Router.pack_and_send(status)

      _ ->
        Logger.debug("Unsupported message ID requested: #{msg_id}")
        send_ack(command_msg, :mav_result_unsupported, source_system, source_component)
    end
  end

  # Request camera information
  defp handle_request_camera_information(command_msg, source_system, source_component, state) do
    send_ack(command_msg, :mav_result_accepted, source_system, source_component)

    camera_info = MessageBuilder.build_camera_information(state)
    Router.pack_and_send(camera_info)
  end

  # Request video stream information
  defp handle_request_video_stream_information(
         command_msg,
         source_system,
         source_component,
         state
       ) do
    send_ack(command_msg, :mav_result_accepted, source_system, source_component)

    stream_info = MessageBuilder.build_video_stream_information(state)
    Router.pack_and_send(stream_info)
  end

  # Request camera settings
  defp handle_request_camera_settings(command_msg, source_system, source_component, state) do
    send_ack(command_msg, :mav_result_accepted, source_system, source_component)

    settings = MessageBuilder.build_camera_settings(state)
    Router.pack_and_send(settings)
  end

  # Request video stream status
  defp handle_request_video_stream_status(command_msg, source_system, source_component, state) do
    send_ack(command_msg, :mav_result_accepted, source_system, source_component)

    status = MessageBuilder.build_video_stream_status(state)
    Router.pack_and_send(status)
  end

  # Request camera capture status (unsupported)
  defp handle_request_capture_status(command_msg, source_system, source_component, _state) do
    send_ack(command_msg, :mav_result_unsupported, source_system, source_component)
  end

  # Request storage information (ACK only)
  defp handle_request_storage_information(command_msg, source_system, source_component, _state) do
    send_ack(command_msg, :mav_result_accepted, source_system, source_component)
  end

  # Set camera zoom (no-op)
  defp handle_set_camera_zoom(command_msg, source_system, source_component, _state) do
    send_ack(command_msg, :mav_result_accepted, source_system, source_component)
  end

  # Send command acknowledgement
  defp send_ack(command_msg, result, source_system, source_component) do
    # Send ACK back to the source of the command
    ack =
      MessageBuilder.build_command_ack(
        command_msg.command,
        result,
        source_system,
        source_component
      )

    Router.pack_and_send(ack)
  end
end
