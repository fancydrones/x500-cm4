defmodule AnnouncerEx.ConfigTest do
  use ExUnit.Case, async: false
  alias AnnouncerEx.Config

  describe "camera configuration" do
    test "camera_id returns integer from application config" do
      assert Config.camera_id!() == 100
    end

    test "camera_name returns string from application config" do
      assert Config.camera_name!() == "Test Camera"
    end

    test "camera_url returns string from application config" do
      assert Config.camera_url!() == "rtsp://test:554/stream"
    end

    test "system_id returns integer from application config" do
      assert Config.system_id!() == 1
    end

    test "system_id defaults to 1 when not configured" do
      # Temporarily remove the config
      original = Application.get_env(:announcer_ex, :system_id)
      Application.delete_env(:announcer_ex, :system_id)
      assert Config.system_id!() == 1
      # Restore original config
      if original, do: Application.put_env(:announcer_ex, :system_id, original)
    end
  end

  describe "broadcast configuration" do
    test "enable_camera_info_broadcast returns configured value" do
      assert Config.enable_camera_info_broadcast!() == true
    end

    test "enable_camera_info_broadcast defaults to true when not configured" do
      original = Application.get_env(:announcer_ex, :enable_camera_info_broadcast)
      Application.delete_env(:announcer_ex, :enable_camera_info_broadcast)
      assert Config.enable_camera_info_broadcast!() == true
      if original != nil, do: Application.put_env(:announcer_ex, :enable_camera_info_broadcast, original)
    end

    test "enable_stream_status returns configured value" do
      # This is critical: VIDEO_STREAM_STATUS should NOT be broadcast by default
      # It should only be sent when requested via MAV_CMD_REQUEST_MESSAGE
      assert Config.enable_stream_status!() == false
    end

    test "enable_stream_status defaults to false when not configured" do
      original = Application.get_env(:announcer_ex, :enable_stream_status)
      Application.delete_env(:announcer_ex, :enable_stream_status)
      assert Config.enable_stream_status!() == false
      if original != nil, do: Application.put_env(:announcer_ex, :enable_stream_status, original)
    end
  end

  describe "network configuration" do
    test "system_host returns configured value" do
      assert Config.system_host!() == "localhost"
    end

    test "system_host defaults to router service hostname when not configured" do
      original = Application.get_env(:announcer_ex, :system_host)
      Application.delete_env(:announcer_ex, :system_host)
      assert Config.system_host!() == "router-service.rpiuav.svc.cluster.local"
      if original, do: Application.put_env(:announcer_ex, :system_host, original)
    end

    test "system_port returns configured value" do
      assert Config.system_port!() == 14550
    end

    test "system_port defaults to 14560 when not configured" do
      original = Application.get_env(:announcer_ex, :system_port)
      Application.delete_env(:announcer_ex, :system_port)
      assert Config.system_port!() == 14560
      if original, do: Application.put_env(:announcer_ex, :system_port, original)
    end

    test "router_connection_string builds correct UDP connection string" do
      assert Config.router_connection_string!() == "udpout:localhost:14550"
    end
  end
end
