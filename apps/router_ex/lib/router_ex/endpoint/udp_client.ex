defmodule RouterEx.Endpoint.UdpClient do
  @moduledoc """
  UDP Client endpoint handler for MAVLink communication.

  This module manages a UDP client that sends MAVLink messages to a specific
  address and port, and receives responses from that endpoint.

  ## Configuration

      %{
        name: "GCS",
        type: :udp_client,
        address: "10.10.10.70",
        port: 14550,
        allow_msg_ids: nil,      # Optional
        block_msg_ids: []         # Optional
      }

  ## Operation

  The UDP client endpoint:
  1. Opens a UDP socket
  2. Registers itself with RouterCore
  3. Sends MAVLink frames to the configured address:port
  4. Receives MAVLink frames from any source (typically the configured endpoint)
  5. Routes received frames to RouterCore

  ## Differences from UDP Server

  - UDP Client sends to a specific address:port
  - UDP Server listens and tracks multiple clients
  - UDP Client is simpler as it doesn't need client tracking
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
      :socket,
      :connection_id,
      :allow_msg_ids,
      :block_msg_ids,
      :buffer,
      :target_ip
    ]
  end

  ## Client API

  @doc """
  Starts the UDP client endpoint.
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

    connection_id = {:udp_client, name}

    state = %State{
      name: name,
      address: address,
      port: port,
      socket: nil,
      connection_id: connection_id,
      allow_msg_ids: Map.get(config, :allow_msg_ids),
      block_msg_ids: Map.get(config, :block_msg_ids),
      buffer: <<>>,
      target_ip: nil
    }

    # Start UDP client
    send(self(), :start_client)

    {:ok, state}
  end

  @impl true
  def handle_info(:start_client, state) do
    case start_udp_client(state) do
      {:ok, new_state} ->
        Logger.info("UDP client started: #{state.address}:#{state.port}")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error(
          "Failed to start UDP client for #{state.address}:#{state.port}: #{inspect(reason)}"
        )

        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) when socket == state.socket do
    # Append to buffer
    new_buffer = state.buffer <> data

    # Parse MAVLink frames
    {frames, remaining_buffer} = parse_frames(new_buffer)

    # Route each frame to RouterCore
    Enum.each(frames, fn frame ->
      # Add source info to frame metadata
      frame_with_source = Map.put(frame, :udp_source, {ip, port})
      RouterEx.RouterCore.route_message(state.connection_id, frame_with_source)
    end)

    if length(frames) > 0 do
      Logger.info(
        "UDP client received #{byte_size(data)} bytes, parsed #{length(frames)} frames from #{format_address(ip)}:#{port}"
      )
    end

    {:noreply, %{state | buffer: remaining_buffer}}
  end

  @impl true
  def handle_info({:send_frame, frame}, state) do
    case serialize_frame(frame) do
      {:ok, data} ->
        case :gen_udp.send(state.socket, state.target_ip, state.port, data) do
          :ok ->
            Logger.debug("Sent frame to #{state.address}:#{state.port}")
            {:noreply, state}

          {:error, reason} ->
            Logger.error(
              "Failed to send to UDP endpoint #{state.address}:#{state.port}: #{inspect(reason)}"
            )

            {:noreply, state}
        end

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
  def terminate(reason, state) do
    Logger.info(
      "UDP client terminating: #{state.address}:#{state.port}, reason: #{inspect(reason)}"
    )

    # Unregister from RouterCore
    if state.socket do
      RouterEx.RouterCore.unregister_connection(state.connection_id)
      :gen_udp.close(state.socket)
    end

    :ok
  end

  ## Private Functions

  defp start_udp_client(state) do
    # Parse target IP address
    target_ip = parse_ip_address(state.address)

    # Open UDP socket (bind to any available port)
    case :gen_udp.open(0, [:binary, {:active, true}]) do
      {:ok, socket} ->
        # Register with RouterCore
        conn_info = %{
          pid: self(),
          type: :udp_client,
          allow_msg_ids: state.allow_msg_ids,
          block_msg_ids: state.block_msg_ids
        }

        :ok = RouterEx.RouterCore.register_connection(state.connection_id, conn_info)

        {:ok, %{state | socket: socket, target_ip: target_ip}}

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
      {127, 0, 0, 1}
    end
  end

  defp parse_ip_address(addr) when is_tuple(addr), do: addr

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
