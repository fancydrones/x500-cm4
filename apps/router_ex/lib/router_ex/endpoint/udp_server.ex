defmodule RouterEx.Endpoint.UdpServer do
  @moduledoc """
  UDP Server endpoint handler for MAVLink communication.

  This module manages a UDP server that listens for incoming MAVLink messages
  and automatically tracks client addresses for bidirectional communication.

  ## Configuration

      %{
        name: "video0",
        type: :udp_server,
        address: "0.0.0.0",
        port: 14560,
        allow_msg_ids: [0, 4, 76, 322, 323],  # Optional
        block_msg_ids: []                      # Optional
      }

  ## Operation

  The UDP server endpoint:
  1. Opens a UDP socket on specified address and port
  2. Registers itself with RouterCore
  3. Receives MAVLink frames from any client
  4. Tracks client addresses automatically
  5. Routes received frames to RouterCore
  6. Sends frames back to tracked clients
  7. Implements client timeout for inactive clients

  ## Client Tracking

  The server maintains a list of active clients based on recent message activity.
  Clients are automatically added when they send messages and removed after
  a period of inactivity (default: 60 seconds).
  """

  use GenServer
  require Logger
  alias RouterEx.MAVLink.Parser

  @client_timeout 60_000
  @cleanup_interval 30_000

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :address,
      :port,
      :socket,
      :connection_id,
      :allow_msg_ids,
      :block_msg_ids,
      :buffer,
      :clients,
      :cleanup_timer
    ]
  end

  defmodule Client do
    @moduledoc false
    defstruct [:address, :port, :last_seen]
  end

  ## Client API

  @doc """
  Starts the UDP server endpoint.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  ## Server Callbacks

  @impl true
  def init(config) do
    name = Map.fetch!(config, :name)
    address = Map.get(config, :address, "0.0.0.0")
    port = Map.fetch!(config, :port)

    connection_id = {:udp_server, name}

    state = %State{
      name: name,
      address: address,
      port: port,
      socket: nil,
      connection_id: connection_id,
      allow_msg_ids: Map.get(config, :allow_msg_ids),
      block_msg_ids: Map.get(config, :block_msg_ids),
      buffer: %{},
      clients: %{},
      cleanup_timer: nil
    }

    # Start UDP server
    send(self(), :start_server)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_server, state) do
    case start_udp_server(state) do
      {:ok, new_state} ->
        Logger.info("UDP server started: #{state.address}:#{state.port}")

        # Schedule periodic client cleanup
        timer = Process.send_after(self(), :cleanup_clients, @cleanup_interval)

        {:noreply, %{new_state | cleanup_timer: timer}}

      {:error, reason} ->
        Logger.error(
          "Failed to start UDP server on #{state.address}:#{state.port}: #{inspect(reason)}"
        )

        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info(:cleanup_clients, state) do
    now = System.monotonic_time(:millisecond)
    timeout_threshold = now - @client_timeout

    # Remove inactive clients
    active_clients =
      state.clients
      |> Enum.filter(fn {_key, client} ->
        client.last_seen > timeout_threshold
      end)
      |> Enum.into(%{})

    removed_count = map_size(state.clients) - map_size(active_clients)

    if removed_count > 0 do
      Logger.debug("Removed #{removed_count} inactive UDP clients")
    end

    # Schedule next cleanup
    timer = Process.send_after(self(), :cleanup_clients, @cleanup_interval)

    {:noreply, %{state | clients: active_clients, cleanup_timer: timer}}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) when socket == state.socket do
    # Track this client
    client_key = {ip, port}
    now = System.monotonic_time(:millisecond)

    client = %Client{
      address: ip,
      port: port,
      last_seen: now
    }

    new_clients = Map.put(state.clients, client_key, client)

    # Get or create buffer for this client
    client_buffer = Map.get(state.buffer, client_key, <<>>)
    new_buffer = client_buffer <> data

    # Parse MAVLink frames
    {frames, remaining_buffer} = parse_frames(new_buffer)

    # Update buffer for this client
    new_buffers =
      if byte_size(remaining_buffer) > 0 do
        Map.put(state.buffer, client_key, remaining_buffer)
      else
        Map.delete(state.buffer, client_key)
      end

    # Route each frame to RouterCore
    Enum.each(frames, fn frame ->
      # Add source client info to frame metadata
      frame_with_source = Map.put(frame, :udp_source, {ip, port})
      RouterEx.RouterCore.route_message(state.connection_id, frame_with_source)
    end)

    if length(frames) > 0 do
      Logger.info(
        "UDP server received #{byte_size(data)} bytes, parsed #{length(frames)} frames from #{format_address(ip)}:#{port}"
      )
    end

    {:noreply, %{state | clients: new_clients, buffer: new_buffers}}
  end

  @impl true
  def handle_info({:send_frame, frame}, state) do
    case serialize_frame(frame) do
      {:ok, data} ->
        # Send to all active clients
        sent_count =
          Enum.reduce(state.clients, 0, fn {_key, client}, acc ->
            case :gen_udp.send(state.socket, client.address, client.port, data) do
              :ok ->
                acc + 1

              {:error, reason} ->
                Logger.warning(
                  "Failed to send to UDP client #{format_address(client.address)}:#{client.port}: #{inspect(reason)}"
                )

                acc
            end
          end)

        if sent_count > 0 do
          Logger.debug("Sent frame to #{sent_count} UDP clients")
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
      Enum.map(state.clients, fn {_key, client} ->
        %{address: format_address(client.address), port: client.port, last_seen: client.last_seen}
      end)

    {:reply, clients, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "UDP server terminating: #{state.address}:#{state.port}, reason: #{inspect(reason)}"
    )

    # Unregister from RouterCore
    if state.socket do
      RouterEx.RouterCore.unregister_connection(state.connection_id)
      :gen_udp.close(state.socket)
    end

    # Cancel cleanup timer
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    :ok
  end

  ## Private Functions

  defp start_udp_server(state) do
    # Parse address
    address =
      case state.address do
        "0.0.0.0" -> {0, 0, 0, 0}
        addr when is_binary(addr) -> parse_ip_address(addr)
        addr -> addr
      end

    # Open UDP socket
    case :gen_udp.open(state.port, [:binary, {:ip, address}, {:active, true}, {:reuseaddr, true}]) do
      {:ok, socket} ->
        # Register with RouterCore
        conn_info = %{
          pid: self(),
          type: :udp_server,
          allow_msg_ids: state.allow_msg_ids,
          block_msg_ids: state.block_msg_ids
        }

        :ok = RouterEx.RouterCore.register_connection(state.connection_id, conn_info)

        {:ok, %{state | socket: socket}}

      {:error, reason} ->
        {:error, reason}
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
