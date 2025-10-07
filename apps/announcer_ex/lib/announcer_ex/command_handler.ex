defmodule AnnouncerEx.CommandHandler do
  @moduledoc """
  Handles MAVLink camera commands.
  """

  alias AnnouncerEx.MessageBuilder
  alias XMAVLink.Router

  require Logger

  # MAVLink command IDs
  @mav_cmd_request_camera_information 521
  @mav_cmd_request_video_stream_information 2504
  @mav_cmd_request_camera_settings 522
  @mav_cmd_request_video_stream_status 2505
  @mav_cmd_request_camera_capture_status 527
  @mav_cmd_request_storage_information 525
  @mav_cmd_set_camera_zoom 531

  @doc """
  Handle a command from a COMMAND_LONG message.
  """
  def handle_command(command_msg, state) do
    command_id = command_msg.command
    source_system = command_msg.target_system
    source_component = command_msg.target_component

    Logger.debug("Received command: #{command_id} from #{source_system}/#{source_component}")

    case command_id do
      @mav_cmd_request_camera_information ->
        handle_request_camera_information(command_msg, state)

      @mav_cmd_request_video_stream_information ->
        handle_request_video_stream_information(command_msg, state)

      @mav_cmd_request_camera_settings ->
        handle_request_camera_settings(command_msg, state)

      @mav_cmd_request_video_stream_status ->
        handle_request_video_stream_status(command_msg, state)

      @mav_cmd_request_camera_capture_status ->
        handle_request_capture_status(command_msg, state)

      @mav_cmd_request_storage_information ->
        handle_request_storage_information(command_msg, state)

      @mav_cmd_set_camera_zoom ->
        handle_set_camera_zoom(command_msg, state)

      _ ->
        Logger.debug("Ignoring unknown command: #{command_id}")
        :ok
    end
  end

  # Request camera information
  defp handle_request_camera_information(command_msg, state) do
    send_ack(command_msg, :mav_result_accepted)

    camera_info = MessageBuilder.build_camera_information(state)
    Router.pack_and_send(camera_info)
  end

  # Request video stream information
  defp handle_request_video_stream_information(command_msg, state) do
    send_ack(command_msg, :mav_result_accepted)

    stream_info = MessageBuilder.build_video_stream_information(state)
    Router.pack_and_send(stream_info)
  end

  # Request camera settings
  defp handle_request_camera_settings(command_msg, state) do
    send_ack(command_msg, :mav_result_accepted)

    settings = MessageBuilder.build_camera_settings(state)
    Router.pack_and_send(settings)
  end

  # Request video stream status
  defp handle_request_video_stream_status(command_msg, state) do
    send_ack(command_msg, :mav_result_accepted)

    status = MessageBuilder.build_video_stream_status(state)
    Router.pack_and_send(status)
  end

  # Request camera capture status (unsupported)
  defp handle_request_capture_status(command_msg, _state) do
    send_ack(command_msg, :mav_result_unsupported)
  end

  # Request storage information (ACK only)
  defp handle_request_storage_information(command_msg, _state) do
    send_ack(command_msg, :mav_result_accepted)
  end

  # Set camera zoom (no-op)
  defp handle_set_camera_zoom(command_msg, _state) do
    send_ack(command_msg, :mav_result_accepted)
  end

  # Send command acknowledgement
  defp send_ack(command_msg, result) do
    # Extract the original sender from the frame
    # Note: In COMMAND_LONG, the sender is identified by the frame's source,
    # not the target fields in the message
    ack = MessageBuilder.build_command_ack(
      command_msg.command,
      result,
      command_msg.target_system,
      command_msg.target_component
    )

    Router.pack_and_send(ack)
  end
end
