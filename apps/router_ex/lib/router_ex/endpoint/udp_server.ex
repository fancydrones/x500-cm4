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
        Logger.error("Failed to start UDP server on #{state.address}:#{state.port}: #{inspect(reason)}")
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
      Logger.debug("Received #{length(frames)} frames from #{format_address(ip)}:#{port}")
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
              :ok -> acc + 1
              {:error, reason} ->
                Logger.warning("Failed to send to UDP client #{format_address(client.address)}:#{client.port}: #{inspect(reason)}")
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
    Logger.info("UDP server terminating: #{state.address}:#{state.port}, reason: #{inspect(reason)}")

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

  # Reuse the same frame parsing logic as Serial endpoint
  defp parse_frames(buffer) do
    do_parse_frames(buffer, [])
  end

  defp do_parse_frames(<<>>, frames), do: {Enum.reverse(frames), <<>>}

  defp do_parse_frames(buffer, frames) when byte_size(buffer) < 8 do
    {Enum.reverse(frames), buffer}
  end

  defp do_parse_frames(<<0xFD, payload_len, _rest::binary>> = buffer, frames)
       when byte_size(buffer) >= payload_len + 12 do
    frame_len = payload_len + 12
    <<frame_data::binary-size(frame_len), rest::binary>> = buffer

    case parse_mavlink_frame(frame_data) do
      {:ok, frame} ->
        do_parse_frames(rest, [frame | frames])

      {:error, _reason} ->
        <<_::8, rest::binary>> = buffer
        do_parse_frames(rest, frames)
    end
  end

  defp do_parse_frames(<<0xFE, payload_len, _rest::binary>> = buffer, frames)
       when byte_size(buffer) >= payload_len + 8 do
    frame_len = payload_len + 8
    <<frame_data::binary-size(frame_len), rest::binary>> = buffer

    case parse_mavlink_frame(frame_data) do
      {:ok, frame} ->
        do_parse_frames(rest, [frame | frames])

      {:error, _reason} ->
        <<_::8, rest::binary>> = buffer
        do_parse_frames(rest, frames)
    end
  end

  defp do_parse_frames(<<_::8, rest::binary>>, frames) do
    do_parse_frames(rest, frames)
  end

  defp parse_mavlink_frame(<<0xFD, payload_len, incompat_flags, compat_flags, seq, sysid, compid,
                               msg_id::24-little, payload::binary-size(payload_len),
                               _checksum::16-little, _signature::binary>> = data)
       when byte_size(data) >= payload_len + 12 do
    {:ok,
     %{
       version: 2,
       payload_length: payload_len,
       incompatibility_flags: incompat_flags,
       compatibility_flags: compat_flags,
       sequence: seq,
       source_system: sysid,
       source_component: compid,
       message_id: msg_id,
       payload: payload,
       raw: data
     }}
  end

  defp parse_mavlink_frame(<<0xFE, payload_len, seq, sysid, compid, msg_id,
                               payload::binary-size(payload_len), _checksum::16-little>> = data)
       when byte_size(data) >= payload_len + 8 do
    {:ok,
     %{
       version: 1,
       payload_length: payload_len,
       sequence: seq,
       source_system: sysid,
       source_component: compid,
       message_id: msg_id,
       payload: payload,
       raw: data
     }}
  end

  defp parse_mavlink_frame(_data) do
    {:error, :invalid_frame}
  end

  defp serialize_frame(frame) do
    case Map.get(frame, :raw) do
      nil -> build_mavlink_frame(frame)
      raw when is_binary(raw) -> {:ok, raw}
    end
  end

  defp build_mavlink_frame(%{version: 2} = frame) do
    payload = Map.get(frame, :payload, <<>>)
    payload_len = byte_size(payload)

    data =
      <<0xFD, payload_len, frame.incompatibility_flags, frame.compatibility_flags, frame.sequence,
        frame.source_system, frame.source_component, frame.message_id::24-little, payload::binary,
        0::16-little>>

    {:ok, data}
  end

  defp build_mavlink_frame(%{version: 1} = frame) do
    payload = Map.get(frame, :payload, <<>>)
    payload_len = byte_size(payload)

    data =
      <<0xFE, payload_len, frame.sequence, frame.source_system, frame.source_component,
        frame.message_id, payload::binary, 0::16-little>>

    {:ok, data}
  end

  defp build_mavlink_frame(_frame) do
    {:error, :invalid_frame_format}
  end
end
