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
      autopilot: :mav_autopilot_invalid,
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
    # MAVLink expects vendor_name and model_name as lists of uint8_t, not binary strings
    # Convert string to list of byte values
    vendor = String.slice(state.camera_name, 0, 31)
    model = String.slice(state.camera_name, 0, 31)

    # Convert to list of bytes (integers) and pad to 32 bytes
    vendor_bytes = String.to_charlist(vendor) |> Enum.concat(List.duplicate(0, 32)) |> Enum.take(32)
    model_bytes = String.to_charlist(model) |> Enum.concat(List.duplicate(0, 32)) |> Enum.take(32)

    %Common.Message.CameraInformation{
      time_boot_ms: boot_timestamp(state.boot_time),
      vendor_name: vendor_bytes,
      model_name: model_bytes,
      firmware_version: 1,
      # Use realistic camera specs to avoid division by zero in QGC
      # Typical IMX219 sensor (Raspberry Pi Camera v2)
      focal_length: 3.04,           # mm - realistic value, not 0!
      sensor_size_h: 3.68,          # mm - sensor width, not 0!
      sensor_size_v: 2.76,          # mm - sensor height, not 0!
      resolution_h: 1280,
      resolution_v: 720,
      lens_id: 0,
      flags: MapSet.new([:camera_cap_flags_has_video_stream]),
      cam_definition_version: 0,  # 0 indicates no definition file available
      cam_definition_uri: pad_bytes("", 140)  # Empty string is valid for "no camera definition"
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
      flags: :video_stream_status_flags_running,
      framerate: 30.0,
      resolution_h: 1280,
      resolution_v: 720,
      bitrate: 5000,
      rotation: 0,
      hfov: 63,  # Horizontal field of view in degrees (IMX219 typical)
      name: pad_bytes(state.camera_name, 32),
      uri: pad_bytes(state.stream_url, 160)
    }
  end

  @doc """
  Build all video stream information messages.
  Returns a list of VideoStreamInformation messages, one per stream.

  Supports both single stream (legacy) and multiple streams configuration.
  If state.streams is not set, uses the default stream from state.stream_url.
  """
  def build_all_stream_info(state) do
    streams = Map.get(state, :streams, nil)

    case streams do
      nil ->
        # Legacy single stream mode
        [build_video_stream_information(state)]

      stream_list when is_list(stream_list) and length(stream_list) > 0 ->
        # Multiple streams mode
        count = length(stream_list)

        stream_list
        |> Enum.with_index(1)
        |> Enum.map(fn {stream, idx} ->
          %Common.Message.VideoStreamInformation{
            stream_id: idx,
            count: count,
            type: Map.get(stream, :type, :video_stream_type_rtsp),
            flags: Map.get(stream, :flags, :video_stream_status_flags_running),
            framerate: Map.get(stream, :framerate, 30.0),
            resolution_h: Map.get(stream, :resolution_h, 1280),
            resolution_v: Map.get(stream, :resolution_v, 720),
            bitrate: Map.get(stream, :bitrate, 5000),
            rotation: Map.get(stream, :rotation, 0),
            hfov: Map.get(stream, :hfov, 63),
            name: pad_bytes(Map.get(stream, :name, state.camera_name), 32),
            uri: pad_bytes(Map.get(stream, :uri, ""), 160)
          }
        end)

      _ ->
        # Fallback to single stream
        [build_video_stream_information(state)]
    end
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
      flags: :video_stream_status_flags_running,
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
