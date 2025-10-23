defmodule RouterEx.Endpoint.TcpClient do
  @moduledoc """
  TCP Client endpoint handler for MAVLink communication.

  This module manages a TCP client connection that connects to a remote
  TCP server and routes MAVLink messages bidirectionally.

  ## Configuration

      %{
        name: "RemoteGCS",
        type: :tcp_client,
        address: "192.168.1.100",
        port: 5760,
        allow_msg_ids: nil,      # Optional
        block_msg_ids: []         # Optional
      }

  ## Operation

  The TCP client endpoint:
  1. Connects to the remote TCP server
  2. Registers itself with RouterCore
  3. Sends MAVLink frames to the server
  4. Receives MAVLink frames from the server
  5. Routes frames to RouterCore
  6. Automatically reconnects on disconnect

  ## Reconnection

  If the connection is lost, the client will automatically attempt to
  reconnect every 5 seconds.
  """

  use GenServer
  require Logger

  @reconnect_interval 5_000

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
      :reconnect_timer,
      :target_ip
    ]
  end

  ## Client API

  @doc """
  Starts the TCP client endpoint.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  ## Server Callbacks

  @impl true
  def init(config) do
    name = Map.fetch!(config, :name)
    address = Map.fetch!(config, :address)
    port = Map.fetch!(config, :port)

    connection_id = {:tcp_client, name}

    state = %State{
      name: name,
      address: address,
      port: port,
      socket: nil,
      connection_id: connection_id,
      allow_msg_ids: Map.get(config, :allow_msg_ids),
      block_msg_ids: Map.get(config, :block_msg_ids),
      buffer: <<>>,
      reconnect_timer: nil,
      target_ip: nil
    }

    # Start connection attempt
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_tcp(state) do
      {:ok, new_state} ->
        Logger.info("TCP client connected: #{state.address}:#{state.port}")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Failed to connect to #{state.address}:#{state.port}: #{inspect(reason)}")
        timer = schedule_reconnect()
        {:noreply, %{state | reconnect_timer: timer}}
    end
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect to #{state.address}:#{state.port}")
    send(self(), :connect)
    {:noreply, %{state | reconnect_timer: nil}}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) when socket == state.socket do
    # Append to buffer
    new_buffer = state.buffer <> data

    # Parse MAVLink frames
    {frames, remaining_buffer} = parse_frames(new_buffer)

    # Route each frame to RouterCore
    Enum.each(frames, fn frame ->
      RouterEx.RouterCore.route_message(state.connection_id, frame)
    end)

    if length(frames) > 0 do
      Logger.debug("Received #{length(frames)} frames from #{state.address}:#{state.port}")
    end

    {:noreply, %{state | buffer: remaining_buffer}}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, state) when socket == state.socket do
    Logger.warning("TCP connection closed: #{state.address}:#{state.port}")

    # Unregister and attempt reconnect
    RouterEx.RouterCore.unregister_connection(state.connection_id)

    timer = schedule_reconnect()
    {:noreply, %{state | socket: nil, reconnect_timer: timer}}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, state) when socket == state.socket do
    Logger.error("TCP error on #{state.address}:#{state.port}: #{inspect(reason)}")

    # Unregister and attempt reconnect
    RouterEx.RouterCore.unregister_connection(state.connection_id)

    if state.socket do
      :gen_tcp.close(state.socket)
    end

    timer = schedule_reconnect()
    {:noreply, %{state | socket: nil, reconnect_timer: timer}}
  end

  @impl true
  def handle_info({:send_frame, frame}, state) do
    case state.socket do
      nil ->
        Logger.debug("Cannot send frame, TCP not connected")
        {:noreply, state}

      socket ->
        case serialize_frame(frame) do
          {:ok, data} ->
            case :gen_tcp.send(socket, data) do
              :ok ->
                Logger.debug("Sent frame to #{state.address}:#{state.port}")
                {:noreply, state}

              {:error, reason} ->
                Logger.error("Failed to send to #{state.address}:#{state.port}: #{inspect(reason)}")
                {:noreply, state}
            end

          {:error, reason} ->
            Logger.error("Failed to serialize frame: #{inspect(reason)}")
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_call(:get_connection_id, _from, state) do
    {:reply, state.connection_id, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("TCP client terminating: #{state.address}:#{state.port}, reason: #{inspect(reason)}")

    # Unregister from RouterCore
    if state.socket do
      RouterEx.RouterCore.unregister_connection(state.connection_id)
      :gen_tcp.close(state.socket)
    end

    # Cancel reconnect timer
    if state.reconnect_timer do
      Process.cancel_timer(state.reconnect_timer)
    end

    :ok
  end

  ## Private Functions

  defp connect_tcp(state) do
    # Parse target IP
    target_ip = parse_ip_address(state.address)

    opts = [
      :binary,
      {:packet, 0},
      {:active, true}
    ]

    case :gen_tcp.connect(target_ip, state.port, opts, 5000) do
      {:ok, socket} ->
        # Register with RouterCore
        conn_info = %{
          pid: self(),
          type: :tcp_client,
          allow_msg_ids: state.allow_msg_ids,
          block_msg_ids: state.block_msg_ids
        }

        :ok = RouterEx.RouterCore.register_connection(state.connection_id, conn_info)

        {:ok, %{state | socket: socket, target_ip: target_ip, buffer: <<>>}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_reconnect do
    Process.send_after(self(), :reconnect, @reconnect_interval)
  end

  defp parse_ip_address(addr) when is_binary(addr) do
    parts = String.split(addr, ".")

    if length(parts) == 4 do
      parts
      |> Enum.map(&String.to_integer/1)
      |> List.to_tuple()
    else
      {127, 0, 0, 1}
    end
  end

  defp parse_ip_address(addr) when is_tuple(addr), do: addr

  # Reuse the same frame parsing logic
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
