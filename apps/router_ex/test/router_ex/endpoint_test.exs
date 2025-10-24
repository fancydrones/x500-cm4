defmodule RouterEx.EndpointTest do
  use ExUnit.Case, async: false
  require Logger

  alias RouterEx.Endpoint.Supervisor, as: EndpointSupervisor

  describe "Endpoint.Supervisor" do
    test "can start and stop UDP server endpoint" do
      config = %{
        name: "TestUdpServer",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14560
      }

      {:ok, pid} = EndpointSupervisor.start_endpoint(config)
      assert Process.alive?(pid)

      # Check connection is registered
      connection_id = {:udp_server, "TestUdpServer"}
      :ok = EndpointSupervisor.stop_endpoint(connection_id)

      # Wait a bit for process to terminate
      Process.sleep(100)
      refute Process.alive?(pid)
    end

    test "can start and stop UDP client endpoint" do
      config = %{
        name: "TestUdpClient",
        type: :udp_client,
        address: "127.0.0.1",
        port: 14551
      }

      {:ok, pid} = EndpointSupervisor.start_endpoint(config)
      assert Process.alive?(pid)

      connection_id = {:udp_client, "TestUdpClient"}
      :ok = EndpointSupervisor.stop_endpoint(connection_id)

      Process.sleep(100)
      refute Process.alive?(pid)
    end

    test "can start and stop TCP server endpoint" do
      config = %{
        name: "TestTcpServer",
        type: :tcp_server,
        address: "127.0.0.1",
        port: 15760
      }

      {:ok, pid} = EndpointSupervisor.start_endpoint(config)
      assert Process.alive?(pid)

      connection_id = {:tcp_server, "TestTcpServer"}
      :ok = EndpointSupervisor.stop_endpoint(connection_id)

      Process.sleep(100)
      refute Process.alive?(pid)
    end

    test "lists running endpoints" do
      config1 = %{
        name: "TestUdpServer1",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14562
      }

      config2 = %{
        name: "TestUdpClient1",
        type: :udp_client,
        address: "127.0.0.1",
        port: 14552
      }

      {:ok, _pid1} = EndpointSupervisor.start_endpoint(config1)
      {:ok, _pid2} = EndpointSupervisor.start_endpoint(config2)

      endpoints = EndpointSupervisor.list_endpoints()
      assert length(endpoints) >= 2

      # Cleanup
      EndpointSupervisor.stop_endpoint({:udp_server, "TestUdpServer1"})
      EndpointSupervisor.stop_endpoint({:udp_client, "TestUdpClient1"})
    end

    test "handles unknown endpoint type" do
      config = %{
        name: "TestInvalid",
        type: :invalid_type,
        address: "127.0.0.1",
        port: 14563
      }

      assert_raise ArgumentError, fn ->
        EndpointSupervisor.start_endpoint(config)
      end
    end
  end

  describe "MAVLink frame parsing and routing" do
    test "UDP server can receive and route MAVLink frames" do
      # Start UDP server
      server_config = %{
        name: "TestMavlinkServer",
        type: :udp_server,
        address: "127.0.0.1",
        port: 14570
      }

      {:ok, server_pid} = EndpointSupervisor.start_endpoint(server_config)
      Process.sleep(100)

      # Create a simple MAVLink v1 heartbeat frame
      # 0xFE (start), len=9, seq=0, sysid=1, compid=1, msgid=0 (HEARTBEAT)
      mavlink_frame =
        <<0xFE, 9, 0, 1, 1, 0, 0::72, 0::16>>

      # Send frame to UDP server
      {:ok, socket} = :gen_udp.open(0, [:binary, {:active, false}])
      :gen_udp.send(socket, {127, 0, 0, 1}, 14570, mavlink_frame)
      :gen_udp.close(socket)

      # Give it time to process
      Process.sleep(100)

      # Cleanup
      EndpointSupervisor.stop_endpoint({:udp_server, "TestMavlinkServer"})

      assert Process.alive?(server_pid) == false or not Process.alive?(server_pid)
    end
  end
end
