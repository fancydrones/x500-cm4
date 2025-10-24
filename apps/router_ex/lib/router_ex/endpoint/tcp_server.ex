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

        # Start acceptor process
        acceptor_pid = spawn_link(fn -> accept_loop(new_state.listen_socket, self()) end)

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
    client_pid =
      spawn_link(fn ->
        handle_client(client_socket, client_info, state.connection_id)
      end)

    # Track this client
    client_id = make_ref()

    new_clients =
      Map.put(state.clients, client_id, %{
        pid: client_pid,
        socket: client_socket,
        info: client_info
      })

    Logger.info(
      "TCP client connected: #{client_info.address}:#{client_info.port} (#{map_size(new_clients)} total)"
    )

    {:noreply, %{state | clients: new_clients}}
  end

  @impl true
  def handle_info({:client_disconnected, client_pid}, state) do
    # Remove client from tracking
    new_clients =
      state.clients
      |> Enum.reject(fn {_id, client} -> client.pid == client_pid end)
      |> Enum.into(%{})

    Logger.info("TCP client disconnected (#{map_size(new_clients)} remaining)")

    {:noreply, %{state | clients: new_clients}}
  end

  @impl true
  def handle_info({:send_frame, frame}, state) do
    case serialize_frame(frame) do
      {:ok, data} ->
        # Send to all connected clients
        sent_count =
          Enum.reduce(state.clients, 0, fn {_id, client}, acc ->
            case :gen_tcp.send(client.socket, data) do
              :ok ->
                acc + 1

              {:error, reason} ->
                Logger.warning("Failed to send to TCP client: #{inspect(reason)}")
                acc
            end
          end)

        if sent_count > 0 do
          Logger.debug("Sent frame to #{sent_count} TCP clients")
        end

        {:noreply, state}

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
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # Get client info
        {:ok, {address, port}} = :inet.peername(client_socket)

        client_info = %{
          address: format_address(address),
          port: port
        }

        # Notify server about new client
        send(server_pid, {:client_connected, client_socket, client_info})

        # Continue accepting
        accept_loop(listen_socket, server_pid)

      {:error, :closed} ->
        Logger.info("TCP accept loop terminated: socket closed")

      {:error, reason} ->
        Logger.error("TCP accept error: #{inspect(reason)}")
        Process.sleep(1000)
        accept_loop(listen_socket, server_pid)
    end
  end

  defp handle_client(socket, client_info, connection_id) do
    Logger.debug("Handling TCP client: #{client_info.address}:#{client_info.port}")

    # Set socket to active mode for this process
    :inet.setopts(socket, active: true)

    # Enter receive loop
    client_loop(socket, <<>>, connection_id)
  end

  defp client_loop(socket, buffer, connection_id) do
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
        client_loop(socket, remaining_buffer, connection_id)

      {:tcp_closed, ^socket} ->
        Logger.debug("TCP client closed connection")
        send(self(), {:client_disconnected, self()})

      {:tcp_error, ^socket, reason} ->
        Logger.error("TCP client error: #{inspect(reason)}")
        :gen_tcp.close(socket)
        send(self(), {:client_disconnected, self()})
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
