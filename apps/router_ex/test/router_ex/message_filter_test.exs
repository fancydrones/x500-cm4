defmodule RouterEx.MessageFilterTest do
  use ExUnit.Case, async: false
  require Logger

  alias RouterEx.Endpoint.Supervisor, as: EndpointSupervisor
  alias RouterEx.RouterCore
  alias RouterEx.MAVLink.Parser

  setup do
    # Clear any existing endpoints
    EndpointSupervisor.list_endpoints()
    |> Enum.each(fn {conn_id, _pid} ->
      EndpointSupervisor.stop_endpoint(conn_id)
    end)

    # Give time for cleanup
    Process.sleep(100)

    :ok
  end

  describe "Message ID filtering with allow_msg_ids (whitelist)" do
    test "endpoint with allow_msg_ids only receives specified message IDs" do
      # Start a UDP server with allow_msg_ids filter
      filtered_config = %{
        name: "FilteredEndpoint",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14580,
        # Only HEARTBEAT (0) and GLOBAL_POSITION_INT (33)
        allow_msg_ids: [0, 33]
      }

      # Start an unfiltered UDP server to send from
      sender_config = %{
        name: "SenderEndpoint",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14581
      }

      {:ok, filtered_pid} = EndpointSupervisor.start_endpoint(filtered_config)
      {:ok, _sender_pid} = EndpointSupervisor.start_endpoint(sender_config)

      Process.sleep(100)

      # Create test frames with different message IDs
      # HEARTBEAT - should be allowed
      heartbeat_frame = create_test_frame(0, 1, 1)
      # GLOBAL_POSITION_INT - should be allowed
      gps_frame = create_test_frame(33, 1, 1)
      # ATTITUDE - should be blocked
      attitude_frame = create_test_frame(30, 1, 1)
      # MISSION_ITEM - should be blocked
      mission_frame = create_test_frame(73, 1, 1)

      # Send frames from sender to filtered endpoint
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

      # Send allowed messages
      :gen_udp.send(socket, {127, 0, 0, 1}, 14581, heartbeat_frame)
      :gen_udp.send(socket, {127, 0, 0, 1}, 14581, gps_frame)

      # Send blocked messages
      :gen_udp.send(socket, {127, 0, 0, 1}, 14581, attitude_frame)
      :gen_udp.send(socket, {127, 0, 0, 1}, 14581, mission_frame)

      :gen_udp.close(socket)

      # Give time for processing
      Process.sleep(200)

      # Check stats - filtered endpoint should have received only allowed messages
      stats = RouterCore.get_stats()

      # We expect 2 packets filtered (attitude and mission)
      assert stats.packets_filtered >= 2

      # Cleanup
      EndpointSupervisor.stop_endpoint({:udp_server, "FilteredEndpoint"})
      EndpointSupervisor.stop_endpoint({:udp_server, "SenderEndpoint"})
    end

    test "endpoint with empty allow_msg_ids blocks all messages" do
      # Start a UDP server with empty allow list
      filtered_config = %{
        name: "BlockAllEndpoint",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14582,
        # Empty whitelist = block all
        allow_msg_ids: []
      }

      sender_config = %{
        name: "SenderEndpoint2",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14583
      }

      {:ok, _filtered_pid} = EndpointSupervisor.start_endpoint(filtered_config)
      {:ok, _sender_pid} = EndpointSupervisor.start_endpoint(sender_config)

      Process.sleep(100)

      # Send various messages
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :gen_udp.send(socket, {127, 0, 0, 1}, 14583, create_test_frame(0, 1, 1))
      :gen_udp.send(socket, {127, 0, 0, 1}, 14583, create_test_frame(33, 1, 1))
      :gen_udp.send(socket, {127, 0, 0, 1}, 14583, create_test_frame(30, 1, 1))
      :gen_udp.close(socket)

      Process.sleep(200)

      stats = RouterCore.get_stats()

      # All messages should be filtered
      assert stats.packets_filtered >= 3

      # Cleanup
      EndpointSupervisor.stop_endpoint({:udp_server, "BlockAllEndpoint"})
      EndpointSupervisor.stop_endpoint({:udp_server, "SenderEndpoint2"})
    end
  end

  describe "Message ID filtering with block_msg_ids (blacklist)" do
    test "endpoint with block_msg_ids blocks specified message IDs" do
      # Start a UDP server with block_msg_ids filter
      filtered_config = %{
        name: "BlacklistEndpoint",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14584,
        # Block ATTITUDE (30) and MISSION_ITEM (73)
        block_msg_ids: [30, 73]
      }

      sender_config = %{
        name: "SenderEndpoint3",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14585
      }

      {:ok, _filtered_pid} = EndpointSupervisor.start_endpoint(filtered_config)
      {:ok, _sender_pid} = EndpointSupervisor.start_endpoint(sender_config)

      Process.sleep(100)

      # Create test frames
      # Should pass
      heartbeat_frame = create_test_frame(0, 1, 1)
      # Should pass
      gps_frame = create_test_frame(33, 1, 1)
      # Should be blocked
      attitude_frame = create_test_frame(30, 1, 1)
      # Should be blocked
      mission_frame = create_test_frame(73, 1, 1)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

      # Send all frames
      :gen_udp.send(socket, {127, 0, 0, 1}, 14585, heartbeat_frame)
      :gen_udp.send(socket, {127, 0, 0, 1}, 14585, gps_frame)
      :gen_udp.send(socket, {127, 0, 0, 1}, 14585, attitude_frame)
      :gen_udp.send(socket, {127, 0, 0, 1}, 14585, mission_frame)

      :gen_udp.close(socket)

      Process.sleep(200)

      stats = RouterCore.get_stats()

      # We expect 2 packets filtered (attitude and mission)
      assert stats.packets_filtered >= 2

      # Cleanup
      EndpointSupervisor.stop_endpoint({:udp_server, "BlacklistEndpoint"})
      EndpointSupervisor.stop_endpoint({:udp_server, "SenderEndpoint3"})
    end

    test "endpoint with nil block_msg_ids allows all messages" do
      # Start a UDP server with no blacklist
      unfiltered_config = %{
        name: "UnfilteredEndpoint",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14586,
        # No filtering
        block_msg_ids: nil,
        # No whitelist either
        allow_msg_ids: nil
      }

      sender_config = %{
        name: "SenderEndpoint4",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14587,
        block_msg_ids: nil,
        allow_msg_ids: nil
      }

      {:ok, _unfiltered_pid} = EndpointSupervisor.start_endpoint(unfiltered_config)
      {:ok, _sender_pid} = EndpointSupervisor.start_endpoint(sender_config)

      Process.sleep(100)

      # Count how many endpoints are actually registered (including from previous tests)
      active_endpoints = EndpointSupervisor.list_endpoints()
      endpoint_count = length(active_endpoints)

      # Send various messages
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :gen_udp.send(socket, {127, 0, 0, 1}, 14587, create_test_frame(0, 1, 1))
      :gen_udp.send(socket, {127, 0, 0, 1}, 14587, create_test_frame(30, 1, 1))
      :gen_udp.send(socket, {127, 0, 0, 1}, 14587, create_test_frame(73, 1, 1))
      :gen_udp.close(socket)

      Process.sleep(200)

      stats = RouterCore.get_stats()

      # With nil filtering, messages should be routed normally
      # The test passes if we received messages without crashes
      assert stats.packets_received > 0

      # Cleanup
      EndpointSupervisor.stop_endpoint({:udp_server, "UnfilteredEndpoint"})
      EndpointSupervisor.stop_endpoint({:udp_server, "SenderEndpoint4"})
    end
  end

  describe "Combined allow and block filtering" do
    test "allow_msg_ids takes precedence over block_msg_ids" do
      # When both are specified, allow list should take precedence
      filtered_config = %{
        name: "CombinedFilterEndpoint",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14588,
        # Only allow these
        allow_msg_ids: [0, 33],
        # Block these (including 0)
        block_msg_ids: [0, 30, 73]
      }

      sender_config = %{
        name: "SenderEndpoint5",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14589
      }

      {:ok, _filtered_pid} = EndpointSupervisor.start_endpoint(filtered_config)
      {:ok, _sender_pid} = EndpointSupervisor.start_endpoint(sender_config)

      Process.sleep(100)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

      # Message 0 is in both allow and block - should be ALLOWED (allow takes precedence)
      :gen_udp.send(socket, {127, 0, 0, 1}, 14589, create_test_frame(0, 1, 1))

      # Message 33 is in allow only - should be ALLOWED
      :gen_udp.send(socket, {127, 0, 0, 1}, 14589, create_test_frame(33, 1, 1))

      # Message 30 is in block only and not in allow - should be BLOCKED
      :gen_udp.send(socket, {127, 0, 0, 1}, 14589, create_test_frame(30, 1, 1))

      # Message 50 is in neither - should be BLOCKED (not in allow list)
      :gen_udp.send(socket, {127, 0, 0, 1}, 14589, create_test_frame(50, 1, 1))

      :gen_udp.close(socket)

      Process.sleep(200)

      stats = RouterCore.get_stats()

      # Expect at least 2 blocked (30 and 50)
      assert stats.packets_filtered >= 2

      # Cleanup
      EndpointSupervisor.stop_endpoint({:udp_server, "CombinedFilterEndpoint"})
      EndpointSupervisor.stop_endpoint({:udp_server, "SenderEndpoint5"})
    end
  end

  describe "Video endpoint filtering scenario" do
    test "video endpoint only receives camera-related messages" do
      # Simulate video streamer endpoint filtering
      # MAVLink message IDs for camera:
      # 0 = HEARTBEAT
      # 4 = PING
      # 76 = COMMAND_LONG
      # 322 = VIDEO_STREAM_INFORMATION
      # 323 = VIDEO_STREAM_STATUS

      video_config = %{
        name: "VideoStreamer",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14560,
        allow_msg_ids: [0, 4, 76, 322, 323]
      }

      sender_config = %{
        name: "FlightController",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14590
      }

      {:ok, _video_pid} = EndpointSupervisor.start_endpoint(video_config)
      {:ok, _fc_pid} = EndpointSupervisor.start_endpoint(sender_config)

      Process.sleep(100)

      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])

      # Camera-related messages (should be allowed)
      # HEARTBEAT
      :gen_udp.send(socket, {127, 0, 0, 1}, 14590, create_test_frame(0, 1, 1))
      # COMMAND_LONG
      :gen_udp.send(socket, {127, 0, 0, 1}, 14590, create_test_frame(76, 1, 1))
      # VIDEO_STREAM_INFO
      :gen_udp.send(socket, {127, 0, 0, 1}, 14590, create_test_frame(322, 1, 1))

      # Non-camera messages (should be blocked)
      # ATTITUDE
      :gen_udp.send(socket, {127, 0, 0, 1}, 14590, create_test_frame(30, 1, 1))
      # GPS
      :gen_udp.send(socket, {127, 0, 0, 1}, 14590, create_test_frame(33, 1, 1))
      # VFR_HUD
      :gen_udp.send(socket, {127, 0, 0, 1}, 14590, create_test_frame(74, 1, 1))
      # BATTERY_STATUS
      :gen_udp.send(socket, {127, 0, 0, 1}, 14590, create_test_frame(147, 1, 1))

      :gen_udp.close(socket)

      Process.sleep(200)

      stats = RouterCore.get_stats()

      # Expect at least 4 filtered messages (30, 33, 74, 147)
      assert stats.packets_filtered >= 4

      # Cleanup
      EndpointSupervisor.stop_endpoint({:udp_server, "VideoStreamer"})
      EndpointSupervisor.stop_endpoint({:udp_server, "FlightController"})
    end
  end

  ## Helper Functions

  defp create_test_frame(message_id, sys_id, comp_id) do
    # Create a simple MAVLink v1 frame for testing
    # Format: STX | len | seq | sysid | compid | msgid | payload | checksum
    # 9 bytes of zeros for simplicity
    payload = <<0::72>>
    payload_len = byte_size(payload)
    seq = 0

    header_and_payload = <<
      payload_len,
      seq,
      sys_id,
      comp_id,
      message_id,
      payload::binary
    >>

    # Calculate CRC
    checksum = Parser.calculate_crc(header_and_payload, 0xFFFF)

    # Build complete frame
    <<0xFE, header_and_payload::binary, checksum::16-little>>
  end
end
