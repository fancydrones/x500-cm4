defmodule AnnouncerEx.MessageBuilder do
  @moduledoc """
  Builds MAVLink messages for the camera component.
  """

  alias XMAVLink.Dialect.Common.Message

  @doc """
  Build a heartbeat message.
  """
  def build_heartbeat do
    %Message.Heartbeat{
      type: :mav_type_camera,
      autopilot: :mav_autopilot_generic,
      base_mode: 0,
      custom_mode: 0,
      system_status: :mav_state_standby,
      mavlink_version: 3
    }
  end

  @doc """
  Build camera information message.
  """
  def build_camera_information(state) do
    %Message.CameraInformation{
      time_boot_ms: boot_timestamp(state.boot_time),
      vendor_name: pad_bytes(state.camera_name, 32),
      model_name: pad_bytes(state.camera_name, 32),
      firmware_version: 1,
      focal_length: 0.0,
      sensor_size_h: 0.0,
      sensor_size_v: 0.0,
      resolution_h: 1280,
      resolution_v: 720,
      lens_id: 0,
      flags: [:camera_cap_flags_has_video_stream],
      cam_definition_version: 1,
      cam_definition_uri: pad_bytes("", 140),
      gimbal_device_id: 0
    }
  end

  @doc """
  Build video stream information message.
  """
  def build_video_stream_information(state) do
    %Message.VideoStreamInformation{
      stream_id: 1,
      count: 1,
      type: :video_stream_type_rtsp,
      flags: [:video_stream_status_flags_running],
      framerate: 30.0,
      resolution_h: 1280,
      resolution_v: 720,
      bitrate: 5000,
      rotation: 0,
      hfov: 63,
      name: pad_bytes(state.camera_name, 32),
      uri: pad_bytes(state.stream_url, 160)
    }
  end

  @doc """
  Build camera settings message.
  """
  def build_camera_settings(state) do
    %Message.CameraSettings{
      time_boot_ms: boot_timestamp(state.boot_time),
      mode_id: 1,
      zoomLevel: 1.0,
      focusLevel: 1.0
    }
  end

  @doc """
  Build video stream status message.
  """
  def build_video_stream_status(_state) do
    %Message.VideoStreamStatus{
      stream_id: 1,
      flags: [:video_stream_status_flags_running],
      framerate: 30.0,
      resolution_h: 1280,
      resolution_v: 720,
      bitrate: 5000,
      rotation: 0,
      hfov: 63
    }
  end

  @doc """
  Build command acknowledgement message.
  """
  def build_command_ack(command_id, result, source_system, source_component) do
    %Message.CommandAck{
      command: command_id,
      result: result,
      progress: 0,
      result_param2: 0,
      target_system: source_system,
      target_component: source_component
    }
  end

  @doc """
  Calculate milliseconds since boot.
  """
  def boot_timestamp(boot_time) do
    current_time = System.monotonic_time(:millisecond)
    current_time - boot_time
  end

  @doc """
  Pad string to specific byte length.
  Returns a list of bytes (integers 0-255).
  """
  def pad_bytes(str, length) do
    bytes = :binary.bin_to_list(str)
    bytes_length = length(bytes)

    cond do
      bytes_length >= length ->
        Enum.take(bytes, length)

      true ->
        bytes ++ List.duplicate(0, length - bytes_length)
    end
  end
end
