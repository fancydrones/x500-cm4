defmodule AnnouncerEx.MessageBuilder do
  @moduledoc """
  Builds MAVLink messages for the camera component.
  """

  @doc """
  Build a heartbeat message.
  """
  def build_heartbeat do
    %Common.Message.Heartbeat{
      type: :mav_type_camera,
      autopilot: :mav_autopilot_generic,
      base_mode: MapSet.new(),
      custom_mode: 0,
      system_status: :mav_state_standby,
      mavlink_version: 3
    }
  end

  @doc """
  Build camera information message.
  """
  def build_camera_information(state) do
    %Common.Message.CameraInformation{
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
      flags: MapSet.new([:camera_cap_flags_has_video_stream]),
      cam_definition_version: 1,
      cam_definition_uri: pad_bytes("", 140)
    }
  end

  @doc """
  Build video stream information message.
  """
  def build_video_stream_information(state) do
    %Common.Message.VideoStreamInformation{
      stream_id: 1,
      count: 1,
      type: :video_stream_type_rtsp,
      flags: MapSet.new([:video_stream_status_flags_running]),
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
    %Common.Message.CameraSettings{
      time_boot_ms: boot_timestamp(state.boot_time),
      mode_id: :camera_mode_image,
      zoomlevel: 1.0,
      focuslevel: 1.0
    }
  end

  @doc """
  Build video stream status message.
  """
  def build_video_stream_status(_state) do
    %Common.Message.VideoStreamStatus{
      stream_id: 1,
      flags: MapSet.new([:video_stream_status_flags_running]),
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
    %Common.Message.CommandAck{
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
  Returns a binary string padded with null bytes.
  """
  def pad_bytes(str, length) do
    # Get the byte size of the string
    byte_size = byte_size(str)

    cond do
      # String is already longer than or equal to length, truncate it
      byte_size >= length ->
        :binary.part(str, 0, length)

      # String is shorter, pad with null bytes
      true ->
        padding_size = length - byte_size
        str <> :binary.copy(<<0>>, padding_size)
    end
  end
end
