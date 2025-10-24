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
  alias RouterEx.MAVLink.Parser

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
    Parser.parse_frames(buffer)
  end

  defp serialize_frame(frame) do
    Parser.serialize_frame(frame)
  end
end
