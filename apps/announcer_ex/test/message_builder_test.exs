defmodule AnnouncerEx.MessageBuilderTest do
  use ExUnit.Case, async: true
  alias AnnouncerEx.MessageBuilder

  describe "build_heartbeat/0" do
    test "builds heartbeat with correct type and autopilot" do
      heartbeat = MessageBuilder.build_heartbeat()

      assert heartbeat.type == :mav_type_camera
      assert heartbeat.autopilot == :mav_autopilot_invalid
      assert heartbeat.system_status == :mav_state_standby
      assert heartbeat.mavlink_version == 3
    end
  end

  describe "build_camera_information/1" do
    setup do
      state = %{
        camera_name: "TestCamera",
        boot_time: System.monotonic_time(:millisecond)
      }

      {:ok, state: state}
    end

    test "builds camera information with correct vendor and model names as uint8 arrays", %{
      state: state
    } do
      camera_info = MessageBuilder.build_camera_information(state)

      # Verify vendor_name and model_name are lists (uint8 arrays)
      assert is_list(camera_info.vendor_name)
      assert is_list(camera_info.model_name)

      # Verify they are exactly 32 bytes
      assert length(camera_info.vendor_name) == 32
      assert length(camera_info.model_name) == 32

      # Verify all values are valid uint8 (0-255)
      assert Enum.all?(camera_info.vendor_name, &(&1 >= 0 and &1 <= 255))
      assert Enum.all?(camera_info.model_name, &(&1 >= 0 and &1 <= 255))

      # Verify first characters match "TestCamera"
      assert Enum.take(camera_info.vendor_name, 10) == String.to_charlist("TestCamera")
      assert Enum.take(camera_info.model_name, 10) == String.to_charlist("TestCamera")
    end

    test "has non-zero realistic camera specs to prevent division by zero", %{state: state} do
      camera_info = MessageBuilder.build_camera_information(state)

      # These must be non-zero to prevent QGC crashes
      assert camera_info.focal_length > 0
      assert camera_info.sensor_size_h > 0
      assert camera_info.sensor_size_v > 0

      # Verify realistic values (IMX219 specs)
      assert camera_info.focal_length == 3.04
      assert camera_info.sensor_size_h == 3.68
      assert camera_info.sensor_size_v == 2.76
    end

    test "has valid resolution", %{state: state} do
      camera_info = MessageBuilder.build_camera_information(state)

      assert camera_info.resolution_h == 1280
      assert camera_info.resolution_v == 720
    end

    test "has properly encoded firmware version", %{state: state} do
      camera_info = MessageBuilder.build_camera_information(state)

      # Should be version 1.0.0.0 encoded properly
      assert camera_info.firmware_version == 1
    end

    test "has cam_definition_version set to 0 for no definition file", %{state: state} do
      camera_info = MessageBuilder.build_camera_information(state)

      # 0 indicates no camera definition file available
      assert camera_info.cam_definition_version == 0
    end

    test "includes video stream capability flag", %{state: state} do
      camera_info = MessageBuilder.build_camera_information(state)

      assert MapSet.member?(camera_info.flags, :camera_cap_flags_has_video_stream)
    end
  end

  describe "build_video_stream_information/1" do
    setup do
      state = %{
        camera_name: "TestCamera",
        stream_url: "rtsp://10.10.10.2:8554/cam"
      }

      {:ok, state: state}
    end

    test "builds video stream information with correct stream ID and count", %{state: state} do
      stream_info = MessageBuilder.build_video_stream_information(state)

      assert stream_info.stream_id == 1
      assert stream_info.count == 1
    end

    test "has correct stream type and flags", %{state: state} do
      stream_info = MessageBuilder.build_video_stream_information(state)

      assert stream_info.type == :video_stream_type_rtsp
      assert stream_info.flags == :video_stream_status_flags_running
    end

    test "has valid resolution and framerate", %{state: state} do
      stream_info = MessageBuilder.build_video_stream_information(state)

      assert stream_info.resolution_h == 1280
      assert stream_info.resolution_v == 720
      assert stream_info.framerate == 30.0
    end

    test "has non-zero hfov (horizontal field of view)", %{state: state} do
      stream_info = MessageBuilder.build_video_stream_information(state)

      # hfov must be non-zero
      assert stream_info.hfov > 0
      assert stream_info.hfov == 63
    end

    test "includes stream URL", %{state: state} do
      stream_info = MessageBuilder.build_video_stream_information(state)

      # URI should start with the configured stream URL
      uri_string = stream_info.uri |> to_string() |> String.trim_trailing(<<0>>)
      assert String.starts_with?(uri_string, "rtsp://10.10.10.2:8554/cam")
    end
  end

  describe "build_video_stream_status/1" do
    setup do
      state = %{}
      {:ok, state: state}
    end

    test "builds status with matching values to stream information", %{state: state} do
      stream_status = MessageBuilder.build_video_stream_status(state)

      # These values should match VIDEO_STREAM_INFORMATION
      assert stream_status.stream_id == 1
      assert stream_status.flags == :video_stream_status_flags_running
      assert stream_status.framerate == 30.0
      assert stream_status.resolution_h == 1280
      assert stream_status.resolution_v == 720
      assert stream_status.bitrate == 5000
      assert stream_status.rotation == 0
      assert stream_status.hfov == 63
    end
  end

  describe "encode_firmware_version/4" do
    test "encodes version 1.0.0.0 correctly" do
      version = MessageBuilder.encode_firmware_version(1, 0, 0, 0)
      assert version == 0x00000001
    end

    test "encodes version 1.2.3.4 correctly" do
      version = MessageBuilder.encode_firmware_version(1, 2, 3, 4)
      assert version == 0x04030201
    end

    test "encodes version components in correct byte positions" do
      version = MessageBuilder.encode_firmware_version(0xAA, 0xBB, 0xCC, 0xDD)

      # Extract components using bit shifts
      import Bitwise
      major = version &&& 0xFF
      minor = (version >>> 8) &&& 0xFF
      patch = (version >>> 16) &&& 0xFF
      dev = (version >>> 24) &&& 0xFF

      assert major == 0xAA
      assert minor == 0xBB
      assert patch == 0xCC
      assert dev == 0xDD
    end

    test "handles zero values" do
      version = MessageBuilder.encode_firmware_version(0, 0, 0, 0)
      assert version == 0x00000000
    end

    test "handles maximum uint8 values" do
      version = MessageBuilder.encode_firmware_version(255, 255, 255, 255)
      assert version == 0xFFFFFFFF
    end
  end

  describe "pad_bytes/2" do
    test "pads string to specified length with null bytes" do
      result = MessageBuilder.pad_bytes("test", 10)
      assert byte_size(result) == 10
      assert String.starts_with?(result, "test")
    end

    test "truncates string if longer than length" do
      result = MessageBuilder.pad_bytes("verylongstring", 5)
      assert byte_size(result) == 5
      assert result == "veryl"
    end

    test "returns string as-is if exact length" do
      result = MessageBuilder.pad_bytes("exact", 5)
      assert byte_size(result) == 5
      assert result == "exact"
    end

    test "handles empty string" do
      result = MessageBuilder.pad_bytes("", 5)
      assert byte_size(result) == 5
      assert result == <<0, 0, 0, 0, 0>>
    end
  end
end
