defmodule AnnouncerEx.ConfigTest do
  use ExUnit.Case, async: false
  alias AnnouncerEx.Config

  describe "camera configuration" do
    test "camera_id returns integer when CAMERA_ID is set" do
      System.put_env("CAMERA_ID", "100")
      assert Config.camera_id!() == 100
    end

    test "camera_name returns string when CAMERA_NAME is set" do
      System.put_env("CAMERA_NAME", "TestCamera")
      assert Config.camera_name!() == "TestCamera"
    end

    test "camera_url returns string when CAMERA_URL is set" do
      System.put_env("CAMERA_URL", "rtsp://10.10.10.2:8554/cam")
      assert Config.camera_url!() == "rtsp://10.10.10.2:8554/cam"
    end

    test "system_id defaults to 1 when not set" do
      System.delete_env("SYSTEM_ID")
      assert Config.system_id!() == 1
    end

    test "system_id returns integer when SYSTEM_ID is set" do
      System.put_env("SYSTEM_ID", "42")
      assert Config.system_id!() == 42
    end
  end

  describe "broadcast configuration" do
    test "enable_camera_info_broadcast defaults to true when not set" do
      System.delete_env("ENABLE_CAMERA_INFO_BROADCAST")
      assert Config.enable_camera_info_broadcast!() == true
    end

    test "enable_camera_info_broadcast returns true when set to 'true'" do
      System.put_env("ENABLE_CAMERA_INFO_BROADCAST", "true")
      assert Config.enable_camera_info_broadcast!() == true
    end

    test "enable_camera_info_broadcast returns false when set to 'false'" do
      System.put_env("ENABLE_CAMERA_INFO_BROADCAST", "false")
      assert Config.enable_camera_info_broadcast!() == false
    end

    test "enable_stream_status defaults to false when not set" do
      System.delete_env("ENABLE_STREAM_STATUS")
      # This is critical: VIDEO_STREAM_STATUS should NOT be broadcast by default
      # It should only be sent when requested via MAV_CMD_REQUEST_MESSAGE
      assert Config.enable_stream_status!() == false
    end

    test "enable_stream_status returns true when explicitly set to 'true'" do
      System.put_env("ENABLE_STREAM_STATUS", "true")
      assert Config.enable_stream_status!() == true
    end

    test "enable_stream_status returns false when set to 'false'" do
      System.put_env("ENABLE_STREAM_STATUS", "false")
      assert Config.enable_stream_status!() == false
    end
  end

  describe "network configuration" do
    test "system_host defaults to router service hostname" do
      System.delete_env("SYSTEM_HOST")
      assert Config.system_host!() == "router-service.rpiuav.svc.cluster.local"
    end

    test "system_port defaults to 14560" do
      System.delete_env("SYSTEM_PORT")
      assert Config.system_port!() == 14560
    end

    test "router_connection_string builds correct UDP connection string" do
      System.put_env("SYSTEM_HOST", "testhost")
      System.put_env("SYSTEM_PORT", "9999")
      assert Config.router_connection_string!() == "udpout:testhost:9999"
    end
  end
end
