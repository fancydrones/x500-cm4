defmodule RouterEx.Endpoint.TcpServer do
  @moduledoc """
  TCP Server endpoint handler for MAVLink communication.

  This module manages a TCP server that accepts incoming connections from
  MAVLink clients (like QGroundControl) and routes messages bidirectionally.

  ## Configuration

      %{
        name: "QGC",
        type: :tcp_server,
        address: "0.0.0.0",
        port: 5760,
        allow_msg_ids: nil,      # Optional
        block_msg_ids: []         # Optional
      }

  ## Operation

  The TCP server endpoint:
  1. Opens a TCP listening socket on specified address and port
  2. Accepts incoming client connections
  3. Spawns a handler process for each connected client
  4. Routes MAVLink frames between clients and RouterCore
  5. Manages client disconnections gracefully

  ## Architecture

  The TCP server uses a supervisor pattern:
  - Main server process accepts connections
  - Each client connection runs in its own process
  - Client processes are supervised for fault isolation
  """

  use GenServer
  require Logger
  alias RouterEx.MAVLink.Parser

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :address,
      :port,
      :listen_socket,
      :connection_id,
      :allow_msg_ids,
      :block_msg_ids,
      :clients,
      :pid_to_client_id,
      :acceptor_pid
    ]
  end

  ## Client API

  @doc """
  Starts the TCP server endpoint.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  ## Server Callbacks

  @impl true
  def init(config) do
    # Trap exits so we can handle client process crashes
    Process.flag(:trap_exit, true)

    name = Map.fetch!(config, :name)
    address = Map.get(config, :address, "0.0.0.0")
    port = Map.get(config, :port, 5760)

    connection_id = {:tcp_server, name}

    state = %State{
      name: name,
      address: address,
      port: port,
      listen_socket: nil,
      connection_id: connection_id,
      allow_msg_ids: Map.get(config, :allow_msg_ids),
      block_msg_ids: Map.get(config, :block_msg_ids),
      clients: %{},
      pid_to_client_id: %{},
      acceptor_pid: nil
    }

    # Start TCP server
    send(self(), :start_server)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_server, state) do
    case start_tcp_server(state) do
      {:ok, new_state} ->
        Logger.info("TCP server started: #{state.address}:#{state.port}")

        # Start acceptor process - pass server PID explicitly
        server_pid = self()
        acceptor_pid = spawn_link(fn -> accept_loop(new_state.listen_socket, server_pid) end)

        Logger.info("TCP acceptor loop started (PID: #{inspect(acceptor_pid)})")

        {:noreply, %{new_state | acceptor_pid: acceptor_pid}}

      {:error, reason} ->
        Logger.error(
          "Failed to start TCP server on #{state.address}:#{state.port}: #{inspect(reason)}"
        )

        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:client_connected, client_socket, client_info}, state) do
    # Spawn a process to handle this client
    server_pid = self()

    client_pid =
      spawn_link(fn ->
        handle_client(client_socket, client_info, state.connection_id, server_pid)
      end)

    # Track this client
    client_id = make_ref()

    new_clients =
      Map.put(state.clients, client_id, %{
        pid: client_pid,
        socket: client_socket,
        info: client_info
      })

    # Maintain reverse index for O(1) lookups
    new_pid_to_client_id = Map.put(state.pid_to_client_id, client_pid, client_id)

    Logger.info(
      "TCP client connected: #{client_info.address}:#{client_info.port} (#{map_size(new_clients)} total)"
    )

    {:noreply, %{state | clients: new_clients, pid_to_client_id: new_pid_to_client_id}}
  end

  @impl true
  def handle_info({:client_disconnected, client_pid}, state) do
    # Use reverse index for O(1) lookup
    case Map.get(state.pid_to_client_id, client_pid) do
      nil ->
        Logger.warning("Received disconnection for unknown client PID: #{inspect(client_pid)}")
        {:noreply, state}

      client_id ->
        # Remove client from tracking
        new_clients = Map.delete(state.clients, client_id)
        new_pid_to_client_id = Map.delete(state.pid_to_client_id, client_pid)

        Logger.info("TCP client disconnected (#{map_size(new_clients)} remaining)")

        {:noreply, %{state | clients: new_clients, pid_to_client_id: new_pid_to_client_id}}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    # Handle client process exits/crashes - use reverse index for O(1) lookup
    case Map.get(state.pid_to_client_id, pid) do
      nil ->
        # This EXIT is for some other process (maybe the acceptor)
        if pid == state.acceptor_pid do
          Logger.error("TCP acceptor process exited: #{inspect(reason)}")
          {:stop, {:acceptor_exit, reason}, state}
        else
          Logger.warning("Received EXIT from unknown process #{inspect(pid)}: #{inspect(reason)}")
          {:noreply, state}
        end

      client_id ->
        client = Map.get(state.clients, client_id)

        Logger.info(
          "TCP client handler process exited: #{client.info.address}:#{client.info.port}, reason: #{inspect(reason)}"
        )

        # Close the socket (may already be closed, which is fine)
        case :gen_tcp.close(client.socket) do
          :ok ->
            :ok

          {:error, :closed} ->
            Logger.debug("Socket already closed for #{client.info.address}:#{client.info.port}")

          {:error, close_reason} ->
            Logger.warning(
              "Failed to close socket for #{client.info.address}:#{client.info.port}: #{inspect(close_reason)}"
            )
        end

        new_clients = Map.delete(state.clients, client_id)
        new_pid_to_client_id = Map.delete(state.pid_to_client_id, pid)

        Logger.info("TCP client removed (#{map_size(new_clients)} remaining)")

        {:noreply, %{state | clients: new_clients, pid_to_client_id: new_pid_to_client_id}}
    end
  end

  @impl true
  def handle_info({:send_frame, frame}, state) do
    case serialize_frame(frame) do
      {:ok, data} ->
        # Send to all connected clients and track which ones failed
        {sent_count, failed_clients} =
          Enum.reduce(state.clients, {0, []}, fn {client_id, client}, {count, failed} ->
            case :gen_tcp.send(client.socket, data) do
              :ok ->
                {count + 1, failed}

              {:error, :closed} ->
                # Socket is closed, mark for removal
                Logger.warning(
                  "TCP socket closed for #{client.info.address}:#{client.info.port}, removing client"
                )

                {count, [client_id | failed]}

              {:error, reason} ->
                Logger.warning(
                  "Failed to send to TCP client #{client.info.address}:#{client.info.port}: #{inspect(reason)}"
                )

                {count, failed}
            end
          end)

        # Remove failed clients
        new_clients =
          Map.drop(state.clients, failed_clients)

        if sent_count > 0 do
          Logger.debug("Sent frame to #{sent_count} TCP clients")
        end

        if length(failed_clients) > 0 do
          Logger.info("Removed #{length(failed_clients)} disconnected TCP clients")
        end

        {:noreply, %{state | clients: new_clients}}

      {:error, reason} ->
        Logger.error("Failed to serialize frame: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_connection_id, _from, state) do
    {:reply, state.connection_id, state}
  end

  @impl true
  def handle_call(:get_clients, _from, state) do
    clients =
      Enum.map(state.clients, fn {_id, client} ->
        %{address: client.info.address, port: client.info.port}
      end)

    {:reply, clients, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "TCP server terminating: #{state.address}:#{state.port}, reason: #{inspect(reason)}"
    )

    # Unregister from RouterCore
    if state.listen_socket do
      RouterEx.RouterCore.unregister_connection(state.connection_id)
      :gen_tcp.close(state.listen_socket)
    end

    # Close all client connections
    Enum.each(state.clients, fn {_id, client} ->
      :gen_tcp.close(client.socket)
    end)

    :ok
  end

  ## Private Functions

  defp start_tcp_server(state) do
    # Parse address
    address =
      case state.address do
        "0.0.0.0" -> {0, 0, 0, 0}
        addr when is_binary(addr) -> parse_ip_address(addr)
        addr -> addr
      end

    # Open TCP listening socket
    opts = [
      :binary,
      {:ip, address},
      {:packet, 0},
      {:active, false},
      {:reuseaddr, true}
    ]

    case :gen_tcp.listen(state.port, opts) do
      {:ok, listen_socket} ->
        # Register with RouterCore
        conn_info = %{
          pid: self(),
          type: :tcp_server,
          allow_msg_ids: state.allow_msg_ids,
          block_msg_ids: state.block_msg_ids
        }

        :ok = RouterEx.RouterCore.register_connection(state.connection_id, conn_info)

        {:ok, %{state | listen_socket: listen_socket}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp accept_loop(listen_socket, server_pid) do
    Logger.debug("TCP acceptor waiting for connections on socket #{inspect(listen_socket)}")

    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # Get client info
        case :inet.peername(client_socket) do
          {:ok, {address, port}} ->
            client_info = %{
              address: format_address(address),
              port: port
            }

            Logger.info(
              "TCP acceptor accepted connection from #{client_info.address}:#{client_info.port}"
            )

            # Notify server about new client
            send(server_pid, {:client_connected, client_socket, client_info})

            # Continue accepting
            accept_loop(listen_socket, server_pid)

          {:error, reason} ->
            Logger.error("Failed to get peer info: #{inspect(reason)}")
            :gen_tcp.close(client_socket)
            accept_loop(listen_socket, server_pid)
        end

      {:error, :closed} ->
        Logger.info("TCP accept loop terminated: socket closed")

      {:error, reason} ->
        Logger.error("TCP accept error: #{inspect(reason)}")
        Process.sleep(1000)
        accept_loop(listen_socket, server_pid)
    end
  end

  defp handle_client(socket, client_info, connection_id, server_pid) do
    Logger.debug("Handling TCP client: #{client_info.address}:#{client_info.port}")

    # Set socket to active mode for this process
    :inet.setopts(socket, active: true)

    # Enter receive loop
    client_loop(socket, <<>>, connection_id, server_pid)
  end

  defp client_loop(socket, buffer, connection_id, server_pid) do
    receive do
      {:tcp, ^socket, data} ->
        # Append to buffer
        new_buffer = buffer <> data

        # Parse MAVLink frames
        {frames, remaining_buffer} = parse_frames(new_buffer)

        # Route each frame to RouterCore
        Enum.each(frames, fn frame ->
          RouterEx.RouterCore.route_message(connection_id, frame)
        end)

        # Continue loop
        client_loop(socket, remaining_buffer, connection_id, server_pid)

      {:tcp_closed, ^socket} ->
        Logger.debug("TCP client closed connection")
        send(server_pid, {:client_disconnected, self()})

      {:tcp_error, ^socket, reason} ->
        Logger.error("TCP client error: #{inspect(reason)}")
        :gen_tcp.close(socket)
        send(server_pid, {:client_disconnected, self()})
    end
  end

  defp parse_ip_address(addr) when is_binary(addr) do
    parts = String.split(addr, ".")

    if length(parts) == 4 do
      parts
      |> Enum.map(&String.to_integer/1)
      |> List.to_tuple()
    else
      {0, 0, 0, 0}
    end
  end

  defp format_address({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  defp format_address(addr) when is_binary(addr), do: addr

  defp parse_frames(buffer) do
    Parser.parse_frames(buffer)
  end

  defp serialize_frame(frame) do
    Parser.serialize_frame(frame)
  end
end
