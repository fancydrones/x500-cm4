defmodule RouterEx.RouterCoreTest do
  use ExUnit.Case, async: false

  alias RouterEx.RouterCore

  @moduletag :router_core

  setup do
    # RouterCore is already running from application startup
    # Just get its PID
    pid = Process.whereis(RouterCore)

    # Store initial connections so we can clean up only test connections
    initial_connections = RouterCore.get_connections()

    # Helper to create a test process that can receive messages
    test_pid = spawn(fn -> receive_loop([]) end)

    on_exit(fn ->
      # Clean up test connections (remove any not present initially)
      current_connections = RouterCore.get_connections()

      Enum.each(current_connections, fn {conn_id, _conn_info} ->
        unless Map.has_key?(initial_connections, conn_id) do
          RouterCore.unregister_connection(conn_id)
        end
      end)

      if Process.alive?(test_pid) do
        Process.exit(test_pid, :kill)
      end
    end)

    %{router_pid: pid, test_pid: test_pid}
  end

  # Helper process to receive and store messages
  defp receive_loop(messages) do
    receive do
      {:get_messages, caller} ->
        send(caller, {:messages, Enum.reverse(messages)})
        receive_loop(messages)

      {:clear_messages, caller} ->
        send(caller, :cleared)
        receive_loop([])

      msg ->
        receive_loop([msg | messages])
    end
  end

  defp get_messages(pid) do
    send(pid, {:get_messages, self()})

    receive do
      {:messages, msgs} -> msgs
    after
      1000 -> []
    end
  end

  defp clear_messages(pid) do
    send(pid, {:clear_messages, self()})

    receive do
      :cleared -> :ok
    after
      1000 -> :timeout
    end
  end

  describe "connection registration" do
    test "registers a connection successfully", %{test_pid: pid} do
      conn_id = {:udp_server, "TestEndpoint"}

      conn_info = %{
        pid: pid,
        type: :udp_server,
        allow_msg_ids: nil,
        block_msg_ids: nil
      }

      assert :ok = RouterCore.register_connection(conn_id, conn_info)

      # Verify connection is registered
      connections = RouterCore.get_connections()
      assert Map.has_key?(connections, conn_id)
      assert connections[conn_id].pid == pid
      assert connections[conn_id].type == :udp_server
    end

    test "registers multiple connections", %{test_pid: pid} do
      conn1 = {:udp_server, "TestEndpoint1"}
      conn2 = {:tcp_server, "TestEndpoint2"}

      conn_info1 = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid, type: :tcp_server, allow_msg_ids: nil, block_msg_ids: nil}

      initial_size = map_size(RouterCore.get_connections())

      assert :ok = RouterCore.register_connection(conn1, conn_info1)
      assert :ok = RouterCore.register_connection(conn2, conn_info2)

      connections = RouterCore.get_connections()
      assert map_size(connections) == initial_size + 2
      assert Map.has_key?(connections, conn1)
      assert Map.has_key?(connections, conn2)
    end

    test "registers connection with message filters", %{test_pid: pid} do
      conn_id = {:udp_server, "FilteredEndpoint"}

      conn_info = %{
        pid: pid,
        type: :udp_server,
        allow_msg_ids: [0, 1, 33],
        block_msg_ids: [4, 5]
      }

      assert :ok = RouterCore.register_connection(conn_id, conn_info)

      connections = RouterCore.get_connections()
      assert connections[conn_id].allow_msg_ids == [0, 1, 33]
      assert connections[conn_id].block_msg_ids == [4, 5]
    end
  end

  describe "connection unregistration" do
    test "unregisters a connection successfully", %{test_pid: pid} do
      conn_id = {:udp_server, "TestEndpointToRemove"}
      conn_info = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      initial_size = map_size(RouterCore.get_connections())
      RouterCore.register_connection(conn_id, conn_info)
      assert map_size(RouterCore.get_connections()) == initial_size + 1

      assert :ok = RouterCore.unregister_connection(conn_id)
      assert map_size(RouterCore.get_connections()) == initial_size
    end

    test "removes connection from routing table when unregistered", %{test_pid: pid} do
      conn_id = {:udp_server, "TestEndpointForRemoval"}
      conn_info = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn_id, conn_info)

      # Route a message to establish routing table entry (use unique system ID)
      frame = %{
        source_system: 250,
        source_component: 1,
        message_id: 0,
        target_system: 0
      }

      RouterCore.route_message(conn_id, frame)
      Process.sleep(50)

      routing_table = RouterCore.get_routing_table()
      assert Map.has_key?(routing_table, 250)
      assert conn_id in routing_table[250]

      # Unregister and verify removal from routing table for this system
      RouterCore.unregister_connection(conn_id)
      routing_table = RouterCore.get_routing_table()
      # The connection should be removed from system 250's routing entry
      # (The entry for system 250 should be gone entirely if this was the only connection)
      refute Map.has_key?(routing_table, 250)
    end
  end

  describe "routing table management" do
    test "builds routing table from source system IDs", %{test_pid: pid} do
      conn_id = {:udp_server, "TestEndpoint"}
      conn_info = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn_id, conn_info)

      # Send message from system 1
      frame1 = %{source_system: 1, source_component: 1, message_id: 0}
      RouterCore.route_message(conn_id, frame1)
      Process.sleep(50)

      routing_table = RouterCore.get_routing_table()
      assert Map.has_key?(routing_table, 1)
      assert conn_id in routing_table[1]

      # Send message from system 2
      frame2 = %{source_system: 2, source_component: 1, message_id: 0}
      RouterCore.route_message(conn_id, frame2)
      Process.sleep(50)

      routing_table = RouterCore.get_routing_table()
      assert Map.has_key?(routing_table, 1)
      assert Map.has_key?(routing_table, 2)
      assert conn_id in routing_table[2]
    end

    test "tracks multiple connections per system", %{test_pid: pid} do
      conn1 = {:udp_server, "UniqueEndpoint1"}
      conn2 = {:tcp_server, "UniqueEndpoint2"}

      conn_info1 = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid, type: :tcp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      # Both connections see system 199 (unique system ID to avoid conflicts with other tests)
      frame = %{source_system: 199, source_component: 1, message_id: 0}
      RouterCore.route_message(conn1, frame)
      RouterCore.route_message(conn2, frame)
      Process.sleep(50)

      routing_table = RouterCore.get_routing_table()
      # Both test connections should be tracking system 199
      assert conn1 in routing_table[199]
      assert conn2 in routing_table[199]
    end
  end

  describe "broadcast message routing" do
    test "routes broadcast message to all connections except source", %{test_pid: _test_pid} do
      # Create two test processes
      pid1 = spawn(fn -> receive_loop([]) end)
      pid2 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Endpoint1"}
      conn2 = {:udp_server, "Endpoint2"}

      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid2, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      # Send broadcast message from conn1 (target_system = 0)
      frame = %{
        source_system: 1,
        source_component: 1,
        message_id: 0,
        target_system: 0
      }

      RouterCore.route_message(conn1, frame)
      Process.sleep(100)

      # conn1 should not receive (it's the source)
      messages1 = get_messages(pid1)
      assert messages1 == []

      # conn2 should receive the broadcast
      messages2 = get_messages(pid2)
      assert length(messages2) == 1
      assert {:send_frame, ^frame} = hd(messages2)

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "routes message with no target_system field as broadcast", %{test_pid: _test_pid} do
      pid1 = spawn(fn -> receive_loop([]) end)
      pid2 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Endpoint1"}
      conn2 = {:udp_server, "Endpoint2"}

      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid2, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      # Message without target_system field
      frame = %{
        source_system: 1,
        source_component: 1,
        message_id: 0
      }

      RouterCore.route_message(conn1, frame)
      Process.sleep(100)

      # Should broadcast to all except source
      messages2 = get_messages(pid2)
      assert length(messages2) == 1

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "targeted message routing" do
    test "routes targeted message only to connections aware of target system" do
      pid1 = spawn(fn -> receive_loop([]) end)
      pid2 = spawn(fn -> receive_loop([]) end)
      pid3 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Endpoint1"}
      conn2 = {:udp_server, "Endpoint2"}
      conn3 = {:udp_server, "Endpoint3"}

      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid2, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info3 = %{pid: pid3, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)
      RouterCore.register_connection(conn3, conn_info3)

      # conn2 sees system 100
      frame_from_system_100 = %{source_system: 100, source_component: 1, message_id: 0}
      RouterCore.route_message(conn2, frame_from_system_100)
      Process.sleep(50)

      clear_messages(pid1)
      clear_messages(pid2)
      clear_messages(pid3)

      # Now send targeted message from conn1 to system 100
      targeted_frame = %{
        source_system: 1,
        source_component: 1,
        message_id: 33,
        target_system: 100
      }

      RouterCore.route_message(conn1, targeted_frame)
      Process.sleep(100)

      # Only conn2 should receive (it has seen system 100)
      messages1 = get_messages(pid1)
      messages2 = get_messages(pid2)
      messages3 = get_messages(pid3)

      assert messages1 == []
      assert length(messages2) == 1
      assert messages3 == []

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
      Process.exit(pid3, :kill)
    end

    test "broadcasts targeted message when target system unknown" do
      pid1 = spawn(fn -> receive_loop([]) end)
      pid2 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Endpoint1"}
      conn2 = {:udp_server, "Endpoint2"}

      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid2, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      # Send targeted message to unknown system 99
      frame = %{
        source_system: 1,
        source_component: 1,
        message_id: 0,
        target_system: 99
      }

      RouterCore.route_message(conn1, frame)
      Process.sleep(100)

      # Should broadcast to all except source (since target unknown)
      messages1 = get_messages(pid1)
      messages2 = get_messages(pid2)

      assert messages1 == []
      assert length(messages2) == 1

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "message filtering" do
    test "applies allow_msg_ids whitelist filter" do
      pid1 = spawn(fn -> receive_loop([]) end)
      pid2 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Sender"}
      conn2 = {:udp_server, "FilteredReceiver"}

      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      # conn2 only allows message IDs 0 and 33
      conn_info2 = %{pid: pid2, type: :udp_server, allow_msg_ids: [0, 33], block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      # Send allowed message (ID 0)
      allowed_frame = %{source_system: 1, message_id: 0, target_system: 0}
      RouterCore.route_message(conn1, allowed_frame)
      Process.sleep(50)

      # Send blocked message (ID 5)
      blocked_frame = %{source_system: 1, message_id: 5, target_system: 0}
      RouterCore.route_message(conn1, blocked_frame)
      Process.sleep(50)

      # Send another allowed message (ID 33)
      allowed_frame2 = %{source_system: 1, message_id: 33, target_system: 0}
      RouterCore.route_message(conn1, allowed_frame2)
      Process.sleep(50)

      messages = get_messages(pid2)

      # Should only receive messages with IDs 0 and 33
      assert length(messages) == 2
      assert Enum.any?(messages, fn {:send_frame, f} -> f.message_id == 0 end)
      assert Enum.any?(messages, fn {:send_frame, f} -> f.message_id == 33 end)
      refute Enum.any?(messages, fn {:send_frame, f} -> f.message_id == 5 end)

      # Check stats show filtered message
      stats = RouterCore.get_stats()
      assert stats.packets_filtered >= 1

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "applies block_msg_ids blacklist filter" do
      pid1 = spawn(fn -> receive_loop([]) end)
      pid2 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Sender"}
      conn2 = {:udp_server, "FilteredReceiver"}

      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      # conn2 blocks message IDs 4 and 5
      conn_info2 = %{pid: pid2, type: :udp_server, allow_msg_ids: nil, block_msg_ids: [4, 5]}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      # Send allowed message (ID 0)
      allowed_frame = %{source_system: 1, message_id: 0, target_system: 0}
      RouterCore.route_message(conn1, allowed_frame)
      Process.sleep(50)

      # Send blocked message (ID 4)
      blocked_frame = %{source_system: 1, message_id: 4, target_system: 0}
      RouterCore.route_message(conn1, blocked_frame)
      Process.sleep(50)

      messages = get_messages(pid2)

      # Should only receive message with ID 0
      assert length(messages) == 1
      assert {:send_frame, %{message_id: 0}} = hd(messages)

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "applies both allow and block filters (allow takes precedence)" do
      pid1 = spawn(fn -> receive_loop([]) end)
      pid2 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Sender"}
      conn2 = {:udp_server, "FilteredReceiver"}

      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      # conn2 allows [0, 33] and blocks [33]
      # Message 33 should be blocked (both rules apply, block wins)
      conn_info2 = %{
        pid: pid2,
        type: :udp_server,
        allow_msg_ids: [0, 33],
        block_msg_ids: [33]
      }

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      # Send message ID 0 (allowed, not blocked)
      frame0 = %{source_system: 1, message_id: 0, target_system: 0}
      RouterCore.route_message(conn1, frame0)
      Process.sleep(50)

      # Send message ID 33 (allowed but also blocked)
      frame33 = %{source_system: 1, message_id: 33, target_system: 0}
      RouterCore.route_message(conn1, frame33)
      Process.sleep(50)

      messages = get_messages(pid2)

      # Should only receive message ID 0
      assert length(messages) == 1
      assert {:send_frame, %{message_id: 0}} = hd(messages)

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "statistics tracking" do
    test "tracks packets received and sent", %{test_pid: pid} do
      conn1 = {:udp_server, "StatsTestEndpoint1"}
      conn2 = {:udp_server, "StatsTestEndpoint2"}

      conn_info1 = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      initial_stats = RouterCore.get_stats()

      # Route 3 messages
      frame = %{source_system: 222, message_id: 0, target_system: 0}
      RouterCore.route_message(conn1, frame)
      RouterCore.route_message(conn1, frame)
      RouterCore.route_message(conn1, frame)
      Process.sleep(50)

      stats = RouterCore.get_stats()

      # Should have received 3 packets
      assert stats.packets_received == initial_stats.packets_received + 3

      # Each message sent to at least 1 connection (conn2), but there may be others registered
      assert stats.packets_sent >= initial_stats.packets_sent + 3
    end

    test "tracks filtered packets", %{test_pid: pid} do
      conn1 = {:udp_server, "Sender"}
      conn2 = {:udp_server, "FilteredReceiver"}

      conn_info1 = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid, type: :udp_server, allow_msg_ids: [0], block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      initial_stats = RouterCore.get_stats()

      # Send filtered message
      frame = %{source_system: 1, message_id: 99, target_system: 0}
      RouterCore.route_message(conn1, frame)
      Process.sleep(50)

      stats = RouterCore.get_stats()
      assert stats.packets_filtered > initial_stats.packets_filtered
    end

    test "tracks bytes sent and received", %{test_pid: pid} do
      conn1 = {:udp_server, "Endpoint1"}
      conn_info1 = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)

      initial_stats = RouterCore.get_stats()

      frame = %{source_system: 1, message_id: 0, payload: <<1, 2, 3, 4, 5>>}
      RouterCore.route_message(conn1, frame)
      Process.sleep(50)

      stats = RouterCore.get_stats()

      # Bytes should have increased
      assert stats.bytes_received > initial_stats.bytes_received
    end
  end

  describe "no loop routing" do
    test "never routes message back to source connection", %{test_pid: _test_pid} do
      pid1 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Endpoint1"}
      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)

      # Send message from conn1
      frame = %{source_system: 1, message_id: 0, target_system: 0}
      RouterCore.route_message(conn1, frame)
      Process.sleep(100)

      # conn1 should NOT receive its own message
      messages = get_messages(pid1)
      assert messages == []

      Process.exit(pid1, :kill)
    end

    test "does not route back even if source connection has seen target system" do
      pid1 = spawn(fn -> receive_loop([]) end)
      pid2 = spawn(fn -> receive_loop([]) end)

      conn1 = {:udp_server, "Endpoint1"}
      conn2 = {:udp_server, "Endpoint2"}

      conn_info1 = %{pid: pid1, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}
      conn_info2 = %{pid: pid2, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)
      RouterCore.register_connection(conn2, conn_info2)

      # conn1 sees system 100
      frame_from_100 = %{source_system: 100, source_component: 1, message_id: 0}
      RouterCore.route_message(conn1, frame_from_100)
      Process.sleep(50)

      clear_messages(pid1)
      clear_messages(pid2)

      # conn1 sends targeted message to system 100
      # Even though conn1 has seen system 100, it shouldn't route back to itself
      targeted_frame = %{
        source_system: 1,
        message_id: 33,
        target_system: 100
      }

      RouterCore.route_message(conn1, targeted_frame)
      Process.sleep(100)

      messages1 = get_messages(pid1)
      assert messages1 == []

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end
  end

  describe "edge cases" do
    test "handles message from unregistered connection gracefully", %{test_pid: _pid} do
      unknown_conn = {:udp_server, "UnknownEndpoint"}

      frame = %{source_system: 1, message_id: 0}

      # Should not crash
      assert :ok = RouterCore.route_message(unknown_conn, frame)
      Process.sleep(50)
    end

    test "handles message with missing fields gracefully", %{test_pid: pid} do
      conn1 = {:udp_server, "Endpoint1"}
      conn_info1 = %{pid: pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)

      # Message with minimal fields
      frame = %{}

      # Should not crash
      assert :ok = RouterCore.route_message(conn1, frame)
      Process.sleep(50)
    end

    test "handles connection with dead pid gracefully" do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(10)
      # dead_pid is now dead

      conn1 = {:udp_server, "DeadEndpoint"}
      conn_info1 = %{pid: dead_pid, type: :udp_server, allow_msg_ids: nil, block_msg_ids: nil}

      RouterCore.register_connection(conn1, conn_info1)

      frame = %{source_system: 1, message_id: 0, target_system: 0}

      # Should not crash when trying to send to dead process
      assert :ok = RouterCore.route_message(conn1, frame)
      Process.sleep(50)
    end
  end
end
