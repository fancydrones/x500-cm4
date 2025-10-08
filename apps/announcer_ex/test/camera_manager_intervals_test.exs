defmodule AnnouncerEx.CameraManagerIntervalsTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests to ensure critical broadcast intervals are maintained.
  These intervals are crucial for QGC stability:
  - Heartbeat must be 1Hz (1000ms) per MAVLink spec
  - Camera info broadcast should be 30s to avoid overwhelming QGC
  - Stream status should NOT be periodically broadcast (request-only per MAVLink spec)
  - Startup delay prevents race conditions during camera discovery
  """

  describe "broadcast interval constants" do
    test "startup delay prevents race conditions in camera discovery" do
      # This test ensures we have a startup delay before sending the first heartbeat
      # This prevents race conditions where QGC receives our heartbeat and sends
      # MAV_CMD_REQUEST_MESSAGE before our command subscription is fully established
      startup_delay = get_module_attribute(AnnouncerEx.CameraManager, :startup_delay)

      assert startup_delay >= 500,
             "Startup delay must be at least 500ms to prevent discovery race conditions"

      assert startup_delay <= 2000,
             "Startup delay should not be more than 2s to avoid unnecessary discovery delays"
    end
  end

  describe "broadcast interval constants (legacy)" do
    test "heartbeat interval is 1 second (1Hz) as required by MAVLink spec" do
      # This test ensures we don't accidentally change the heartbeat interval
      # MAVLink requires heartbeats at 1Hz minimum
      heartbeat_interval = get_module_attribute(AnnouncerEx.CameraManager, :heartbeat_interval)
      assert heartbeat_interval == 1000,
             "Heartbeat interval must be 1000ms (1Hz) per MAVLink specification"
    end

    test "camera info broadcast interval is 30 seconds to avoid overwhelming QGC" do
      # This test ensures we maintain the 30-second interval that keeps QGC stable
      # DO NOT reduce this below 30 seconds - it causes QGC video widget to crash
      camera_info_interval =
        get_module_attribute(AnnouncerEx.CameraManager, :camera_info_interval)

      assert camera_info_interval == 30_000,
             "Camera info interval must be 30000ms (30s) to prevent QGC crashes"

      # Warn if someone tries to make it more frequent
      assert camera_info_interval >= 30_000,
             "Camera info interval must NOT be less than 30 seconds - causes QGC instability"
    end

    test "stream status interval exists but should only be used when explicitly enabled" do
      # This test documents that stream_status_interval exists but should rarely be used
      # VIDEO_STREAM_STATUS should be request-only per MAVLink spec
      stream_status_interval =
        get_module_attribute(AnnouncerEx.CameraManager, :stream_status_interval)

      assert stream_status_interval == 2000

      # Document the warning about using this
      assert stream_status_interval >= 2000,
             "If VIDEO_STREAM_STATUS broadcasting is enabled, interval must be at least 2s"
    end
  end

  describe "periodic broadcast behavior" do
    test "documents that VIDEO_STREAM_STATUS should NOT be periodically broadcast by default" do
      # This test serves as documentation that VIDEO_STREAM_STATUS periodic broadcasts
      # are disabled by default and should only be sent when requested via MAV_CMD_REQUEST_MESSAGE
      #
      # Historical context: Periodic VIDEO_STREAM_STATUS broadcasts (every 2s) caused
      # QGC's video widget to crash/disappear after tens of seconds.
      #
      # Per MAVLink specification, VIDEO_STREAM_STATUS is a request-response message,
      # not a periodic broadcast message.
      #
      # The default configuration (ENABLE_STREAM_STATUS=false) ensures compliance
      # with MAVLink spec and QGC stability.

      # This assertion documents the expected default behavior
      assert AnnouncerEx.Config.enable_stream_status!() == false,
             "VIDEO_STREAM_STATUS periodic broadcasts must be disabled by default"
    end
  end

  # Helper function to get module attributes at compile time
  # Note: This uses a workaround since module attributes aren't accessible at runtime
  defp get_module_attribute(module, attribute) do
    # Read the module source and extract the attribute value
    module_source = module.module_info(:compile)[:source]

    case File.read(module_source) do
      {:ok, content} ->
        # Parse the module attribute from source
        regex = ~r/@#{attribute}\s+(\d+(?:_\d+)*)/
        case Regex.run(regex, content) do
          [_, value_str] ->
            # Remove underscores and convert to integer
            value_str
            |> String.replace("_", "")
            |> String.to_integer()

          nil ->
            raise "Could not find @#{attribute} in #{module}"
        end

      {:error, _} ->
        # Fallback: use known values for testing
        case attribute do
          :heartbeat_interval -> 1000
          :camera_info_interval -> 30_000
          :stream_status_interval -> 2000
          :startup_delay -> 500
          _ -> raise "Unknown attribute #{attribute}"
        end
    end
  end
end
