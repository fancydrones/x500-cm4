defmodule RouterEx.RouterCore do
  @moduledoc """
  Core routing logic for MAVLink messages.

  RouterCore maintains:
  - Routing table: Maps system IDs to connections that have seen them
  - Connection registry: Tracks all active connections
  - Message statistics: Packets received, sent, and bytes transferred

  ## Message Routing Rules

  1. **System Awareness**: Track which systems have been seen on each connection
  2. **Targeted Messages**: Route to connections aware of the target system
  3. **Broadcast Messages**: Forward to all connections except source
  4. **No Loops**: Never send message back to source connection
  5. **Filtering**: Apply allow/block message ID filters per endpoint
  """

  use GenServer
  require Logger

  # Type for connection identifiers
  @type connection_id :: {atom(), String.t()}
  @type system_id :: non_neg_integer()

  @type connection_info :: %{
          pid: pid(),
          type: atom(),
          allow_msg_ids: [non_neg_integer()] | nil,
          block_msg_ids: [non_neg_integer()] | nil
        }

  @type state :: %{
          # Map: system_id -> MapSet of connection_ids that have seen this system
          routing_table: %{system_id() => MapSet.t(connection_id())},
          # Map: connection_id -> connection info
          connections: %{connection_id() => connection_info()},
          # Statistics
          stats: %{
            packets_received: non_neg_integer(),
            packets_sent: non_neg_integer(),
            bytes_received: non_neg_integer(),
            bytes_sent: non_neg_integer(),
            packets_filtered: non_neg_integer()
          }
        }

  ## Client API

  @doc """
  Starts the RouterCore.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a connection with the router.

  ## Parameters
  - connection_id: Unique identifier for the connection (e.g., {:serial, "FlightController"})
  - connection_info: Map containing pid, type, and optional message filters
  """
  @spec register_connection(connection_id(), connection_info()) :: :ok
  def register_connection(connection_id, connection_info) do
    GenServer.call(__MODULE__, {:register_connection, connection_id, connection_info})
  end

  @doc """
  Unregisters a connection from the router.
  """
  @spec unregister_connection(connection_id()) :: :ok
  def unregister_connection(connection_id) do
    GenServer.call(__MODULE__, {:unregister_connection, connection_id})
  end

  @doc """
  Routes a MAVLink message from a source connection to appropriate destinations.

  This is async (cast) to avoid blocking the sender.
  """
  @spec route_message(connection_id(), map()) :: :ok
  def route_message(source_connection_id, frame) do
    GenServer.cast(__MODULE__, {:route_message, source_connection_id, frame})
  end

  @doc """
  Gets routing statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets all registered connections.

  Returns a map of connection_id => connection_info for all active connections.
  """
  @spec get_connections() :: %{connection_id() => connection_info()}
  def get_connections do
    GenServer.call(__MODULE__, :get_connections)
  end

  @doc """
  Gets the current routing table (for debugging/introspection).
  """
  @spec get_routing_table() :: map()
  def get_routing_table do
    GenServer.call(__MODULE__, :get_routing_table)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Router core starting")

    state = %{
      routing_table: %{},
      connections: %{},
      stats: %{
        packets_received: 0,
        packets_sent: 0,
        bytes_received: 0,
        bytes_sent: 0,
        packets_filtered: 0
      }
    }

    # Schedule periodic stats reporting if enabled
    schedule_stats_report()

    {:ok, state}
  end

  @impl true
  def handle_call({:register_connection, conn_id, conn_info}, _from, state) do
    Logger.info("Registering connection: #{inspect(conn_id)}")

    # Emit telemetry event
    :telemetry.execute(
      [:router_ex, :connection, :registered],
      %{count: 1},
      %{connection_id: conn_id, type: conn_info.type}
    )

    new_connections = Map.put(state.connections, conn_id, conn_info)
    {:reply, :ok, %{state | connections: new_connections}}
  end

  @impl true
  def handle_call({:unregister_connection, conn_id}, _from, state) do
    Logger.info("Unregistering connection: #{inspect(conn_id)}")

    # Emit telemetry event
    :telemetry.execute(
      [:router_ex, :connection, :unregistered],
      %{count: 1},
      %{connection_id: conn_id}
    )

    # Remove from connections
    new_connections = Map.delete(state.connections, conn_id)

    # Remove from routing table
    new_routing_table =
      state.routing_table
      |> Enum.map(fn {sys_id, conn_set} ->
        {sys_id, MapSet.delete(conn_set, conn_id)}
      end)
      |> Enum.reject(fn {_sys_id, conn_set} -> MapSet.size(conn_set) == 0 end)
      |> Enum.into(%{})

    {:reply, :ok, %{state | connections: new_connections, routing_table: new_routing_table}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call(:get_connections, _from, state) do
    {:reply, state.connections, state}
  end

  @impl true
  def handle_call(:get_routing_table, _from, state) do
    # Convert MapSets to lists for easier inspection
    table =
      state.routing_table
      |> Enum.map(fn {sys_id, conn_set} ->
        {sys_id, MapSet.to_list(conn_set)}
      end)
      |> Enum.into(%{})

    {:reply, table, state}
  end

  @impl true
  def handle_cast({:route_message, source_conn_id, frame}, state) do
    # Extract source system ID
    source_system = Map.get(frame, :source_system, 0)

    # Update routing table: source connection has seen this system
    new_routing_table =
      Map.update(
        state.routing_table,
        source_system,
        MapSet.new([source_conn_id]),
        &MapSet.put(&1, source_conn_id)
      )

    # Determine target connections
    {target_conns, filtered_count} =
      determine_targets(frame, source_conn_id, new_routing_table, state.connections)

    # Send to all target connections
    Enum.each(target_conns, fn {conn_id, conn_info} ->
      send_to_connection(conn_id, conn_info, frame)
    end)

    # Log routing for message ID 69 (MANUAL_CONTROL - gimbal commands)
    if Map.get(frame, :message_id) == 69 do
      target_names =
        Enum.map(target_conns, fn {conn_id, _} -> inspect(conn_id) end) |> Enum.join(", ")

      Logger.info(
        "Routing msg_id 69 from #{inspect(source_conn_id)} to: #{target_names} (filtered: #{filtered_count})"
      )
    end

    # Calculate bytes (rough estimate based on message size)
    message_bytes = byte_size(inspect(frame))

    # Update statistics
    new_stats = %{
      state.stats
      | packets_received: state.stats.packets_received + 1,
        packets_sent: state.stats.packets_sent + length(target_conns),
        bytes_received: state.stats.bytes_received + message_bytes,
        bytes_sent: state.stats.bytes_sent + message_bytes * length(target_conns),
        packets_filtered: state.stats.packets_filtered + filtered_count
    }

    # Emit telemetry event
    :telemetry.execute(
      [:router_ex, :message, :routed],
      %{count: 1, targets: length(target_conns), filtered: filtered_count},
      %{source: source_conn_id, source_system: source_system}
    )

    {:noreply, %{state | routing_table: new_routing_table, stats: new_stats}}
  end

  @impl true
  def handle_info(:report_stats, state) do
    general_config = Application.get_env(:router_ex, :general, [])

    if Keyword.get(general_config, :report_stats, false) do
      Logger.info("""
      Router Stats:
        Connections: #{map_size(state.connections)}
        Systems tracked: #{map_size(state.routing_table)}
        Packets received: #{state.stats.packets_received}
        Packets sent: #{state.stats.packets_sent}
        Packets filtered: #{state.stats.packets_filtered}
        Bytes received: #{state.stats.bytes_received}
        Bytes sent: #{state.stats.bytes_sent}
      """)
    end

    schedule_stats_report()
    {:noreply, state}
  end

  ## Private Functions

  defp determine_targets(frame, source_conn_id, routing_table, connections) do
    target_system = get_target_system(frame)

    # Determine candidate connections
    candidates =
      if target_system == 0 do
        # Broadcast: send to all connections except source
        connections
        |> Enum.reject(fn {conn_id, _} -> conn_id == source_conn_id end)
      else
        # Targeted: send to connections that have seen target system
        case Map.get(routing_table, target_system) do
          nil ->
            # Unknown target, broadcast to all except source
            connections
            |> Enum.reject(fn {conn_id, _} -> conn_id == source_conn_id end)

          conn_set ->
            # Send to connections aware of target (except source)
            conn_set
            |> MapSet.delete(source_conn_id)
            |> Enum.map(fn conn_id -> {conn_id, connections[conn_id]} end)
            |> Enum.reject(fn {_id, info} -> is_nil(info) end)
        end
      end

    # Apply filters and count filtered messages
    {filtered, rejected} =
      candidates
      |> Enum.split_with(fn conn -> should_forward?(conn, frame) end)

    {filtered, length(rejected)}
  end

  defp get_target_system(frame) do
    # Try to extract target_system from the frame/message
    # Different message types have different field names
    cond do
      Map.has_key?(frame, :target_system) ->
        frame.target_system

      Map.has_key?(frame, :message) and is_map(frame.message) and
          Map.has_key?(frame.message, :target_system) ->
        frame.message.target_system

      true ->
        # Broadcast - no specific target
        0
    end
  end

  defp should_forward?({_conn_id, conn_info}, frame) do
    msg_id = Map.get(frame, :message_id, 0)

    # Check AllowMsgIdOut (whitelist)
    allowed =
      if allow_list = conn_info[:allow_msg_ids] do
        msg_id in allow_list
      else
        true
      end

    # Check BlockMsgIdOut (blacklist)
    blocked =
      if block_list = conn_info[:block_msg_ids] do
        msg_id in block_list
      else
        false
      end

    allowed and not blocked
  end

  defp send_to_connection(conn_id, conn_info, frame) do
    # Send frame to connection process
    # Connection handler will serialize and transmit
    send(conn_info.pid, {:send_frame, frame})

    Logger.debug("Routed message to #{inspect(conn_id)}")
  end

  defp schedule_stats_report do
    # Report stats every 10 seconds
    Process.send_after(self(), :report_stats, 10_000)
  end
end
