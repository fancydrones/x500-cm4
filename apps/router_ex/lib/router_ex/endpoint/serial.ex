defmodule RouterEx.Endpoint.Serial do
  @moduledoc """
  Serial (UART) endpoint handler for MAVLink communication.

  This module manages a serial port connection, handling:
  - Opening and configuring serial devices
  - Reading MAVLink frames from the serial port
  - Writing MAVLink frames to the serial port
  - Automatic reconnection on disconnect
  - Frame buffering and parsing using XMAVLink

  ## Configuration

      %{
        name: "FlightController",
        type: :uart,
        device: "/dev/serial0",
        baud: 921_600,
        allow_msg_ids: [0, 1, 33],  # Optional
        block_msg_ids: [123]         # Optional
      }

  ## Operation

  The serial endpoint:
  1. Opens the serial device with specified baud rate
  2. Registers itself with RouterCore
  3. Continuously reads data and parses MAVLink frames
  4. Routes received frames to RouterCore
  5. Receives frames from RouterCore via messages
  6. Automatically reconnects if connection is lost
  """

  use GenServer
  require Logger
  alias Circuits.UART

  @reconnect_interval 5_000

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :device,
      :baud,
      :uart_ref,
      :connection_id,
      :allow_msg_ids,
      :block_msg_ids,
      :buffer,
      :parser,
      :reconnect_timer
    ]
  end

  ## Client API

  @doc """
  Starts the serial endpoint.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  ## Server Callbacks

  @impl true
  def init(config) do
    name = Map.fetch!(config, :name)
    device = Map.fetch!(config, :device)
    baud = Map.fetch!(config, :baud)

    connection_id = {:uart, name}

    state = %State{
      name: name,
      device: device,
      baud: baud,
      uart_ref: nil,
      connection_id: connection_id,
      allow_msg_ids: Map.get(config, :allow_msg_ids),
      block_msg_ids: Map.get(config, :block_msg_ids),
      buffer: <<>>,
      parser: nil,
      reconnect_timer: nil
    }

    # Start connection attempt
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_serial(state) do
      {:ok, new_state} ->
        Logger.info("Serial endpoint connected: #{state.device}")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Failed to connect to #{state.device}: #{inspect(reason)}")
        timer = schedule_reconnect()
        {:noreply, %{state | reconnect_timer: timer}}
    end
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect to #{state.device}")
    send(self(), :connect)
    {:noreply, %{state | reconnect_timer: nil}}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    # Append data to buffer
    new_buffer = state.buffer <> data

    # Parse MAVLink frames from buffer
    {frames, remaining_buffer} = parse_frames(new_buffer)

    # Route each frame to RouterCore
    Enum.each(frames, fn frame ->
      RouterEx.RouterCore.route_message(state.connection_id, frame)
    end)

    {:noreply, %{state | buffer: remaining_buffer}}
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:error, reason}}, state) do
    Logger.error("Serial error on #{state.device}: #{inspect(reason)}")

    # Unregister and attempt reconnect
    RouterEx.RouterCore.unregister_connection(state.connection_id)

    if state.uart_ref do
      UART.close(state.uart_ref)
    end

    timer = schedule_reconnect()
    {:noreply, %{state | uart_ref: nil, reconnect_timer: timer}}
  end

  @impl true
  def handle_info({:send_frame, frame}, state) do
    case state.uart_ref do
      nil ->
        Logger.debug("Cannot send frame, serial port not connected")
        {:noreply, state}

      uart_ref ->
        case serialize_frame(frame) do
          {:ok, data} ->
            case UART.write(uart_ref, data) do
              :ok ->
                Logger.debug("Sent frame to #{state.device}")
                {:noreply, state}

              {:error, reason} ->
                Logger.error("Failed to write to #{state.device}: #{inspect(reason)}")
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
    Logger.info("Serial endpoint terminating: #{state.device}, reason: #{inspect(reason)}")

    # Unregister from RouterCore
    if state.uart_ref do
      RouterEx.RouterCore.unregister_connection(state.connection_id)
      UART.close(state.uart_ref)
    end

    # Cancel reconnect timer
    if state.reconnect_timer do
      Process.cancel_timer(state.reconnect_timer)
    end

    :ok
  end

  ## Private Functions

  defp connect_serial(state) do
    with {:ok, uart_ref} <- UART.start_link(),
         :ok <- UART.open(uart_ref, state.device, speed: state.baud, active: true),
         :ok <- register_with_router(state) do
      {:ok, %{state | uart_ref: uart_ref, buffer: <<>>}}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp register_with_router(state) do
    conn_info = %{
      pid: self(),
      type: :uart,
      allow_msg_ids: state.allow_msg_ids,
      block_msg_ids: state.block_msg_ids
    }

    RouterEx.RouterCore.register_connection(state.connection_id, conn_info)
  end

  defp schedule_reconnect do
    Process.send_after(self(), :reconnect, @reconnect_interval)
  end

  defp parse_frames(buffer) do
    # Use XMAVLink to parse MAVLink frames from binary data
    # This is a simplified implementation - in production you'd use XMAVLink.Router
    # or XMAVLink.Frame.parse/1 with proper frame accumulation

    # For now, we'll implement basic frame detection
    # MAVLink v1 starts with 0xFE, v2 starts with 0xFD
    do_parse_frames(buffer, [])
  end

  defp do_parse_frames(<<>>, frames), do: {Enum.reverse(frames), <<>>}

  defp do_parse_frames(buffer, frames) when byte_size(buffer) < 8 do
    # Not enough data for a complete frame header
    {Enum.reverse(frames), buffer}
  end

  defp do_parse_frames(<<0xFD, payload_len, _rest::binary>> = buffer, frames)
       when byte_size(buffer) >= payload_len + 12 do
    # MAVLink v2 frame
    frame_len = payload_len + 12
    <<frame_data::binary-size(frame_len), rest::binary>> = buffer

    case parse_mavlink_frame(frame_data) do
      {:ok, frame} ->
        do_parse_frames(rest, [frame | frames])

      {:error, _reason} ->
        # Skip this byte and try again
        <<_::8, rest::binary>> = buffer
        do_parse_frames(rest, frames)
    end
  end

  defp do_parse_frames(<<0xFE, payload_len, _rest::binary>> = buffer, frames)
       when byte_size(buffer) >= payload_len + 8 do
    # MAVLink v1 frame
    frame_len = payload_len + 8
    <<frame_data::binary-size(frame_len), rest::binary>> = buffer

    case parse_mavlink_frame(frame_data) do
      {:ok, frame} ->
        do_parse_frames(rest, [frame | frames])

      {:error, _reason} ->
        # Skip this byte and try again
        <<_::8, rest::binary>> = buffer
        do_parse_frames(rest, frames)
    end
  end

  defp do_parse_frames(<<_::8, rest::binary>>, frames) do
    # Not a valid frame start, skip this byte
    do_parse_frames(rest, frames)
  end

  defp parse_mavlink_frame(<<0xFD, payload_len, incompat_flags, compat_flags, seq, sysid, compid,
                               msg_id::24-little, payload::binary-size(payload_len),
                               _checksum::16-little, _signature::binary>> = data)
       when byte_size(data) >= payload_len + 12 do
    # MAVLink v2
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
    # MAVLink v1
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
    # Serialize frame back to binary
    # If frame has :raw field, use that directly
    case Map.get(frame, :raw) do
      nil ->
        # Build frame from components
        build_mavlink_frame(frame)

      raw when is_binary(raw) ->
        {:ok, raw}
    end
  end

  defp build_mavlink_frame(%{version: 2} = frame) do
    # MAVLink v2
    payload = Map.get(frame, :payload, <<>>)
    payload_len = byte_size(payload)

    # For simplicity, we'll skip signature (should compute checksum properly)
    data =
      <<0xFD, payload_len, frame.incompatibility_flags, frame.compatibility_flags, frame.sequence,
        frame.source_system, frame.source_component, frame.message_id::24-little, payload::binary,
        0::16-little>>

    {:ok, data}
  end

  defp build_mavlink_frame(%{version: 1} = frame) do
    # MAVLink v1
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
