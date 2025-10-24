defmodule RouterEx.HealthMonitor do
  @moduledoc """
  Connection health monitoring for Router-Ex endpoints.

  This module provides health checks and status reporting for all
  registered connections, enabling monitoring and diagnostics.

  ## Features

  - Health checks for all endpoints
  - Connection status reporting
  - Uptime tracking
  - Last message timestamp tracking
  - Active connection counting

  ## Usage

      # Get overall health status
      health = RouterEx.HealthMonitor.get_health()

      # Get detailed status for all connections
      status = RouterEx.HealthMonitor.get_connection_status()

      # Get status for specific connection
      status = RouterEx.HealthMonitor.get_connection_status(connection_id)

      # Check if system is healthy
      healthy? = RouterEx.HealthMonitor.healthy?()
  """

  use GenServer
  require Logger

  # 10 seconds
  @check_interval 10_000
  # 60 seconds without activity
  @unhealthy_threshold 60_000

  defmodule State do
    @moduledoc false
    defstruct [
      :start_time,
      :last_check,
      :connection_health
    ]
  end

  ## Client API

  @doc """
  Starts the health monitor.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Gets overall system health status.

  Returns a map with:
  - `:status` - `:healthy`, `:degraded`, or `:unhealthy`
  - `:uptime` - System uptime in milliseconds
  - `:total_connections` - Total number of registered connections
  - `:healthy_connections` - Number of healthy connections
  - `:unhealthy_connections` - Number of unhealthy connections
  - `:last_check` - Timestamp of last health check

  ## Examples

      iex> RouterEx.HealthMonitor.get_health()
      %{
        status: :healthy,
        uptime: 123456,
        total_connections: 5,
        healthy_connections: 5,
        unhealthy_connections: 0,
        last_check: ~U[2025-10-23 21:00:00Z]
      }
  """
  @spec get_health() :: map()
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @doc """
  Gets detailed connection status for all connections or a specific connection.

  ## Examples

      # Get all connection statuses
      iex> RouterEx.HealthMonitor.get_connection_status()
      [
        %{
          connection_id: {:udp_server, "video0"},
          type: :udp_server,
          status: :healthy,
          last_activity: ~U[2025-10-23 21:00:00Z],
          messages_received: 1234,
          messages_sent: 567
        }
      ]

      # Get specific connection status
      iex> RouterEx.HealthMonitor.get_connection_status({:udp_server, "video0"})
      %{
        connection_id: {:udp_server, "video0"},
        type: :udp_server,
        status: :healthy,
        ...
      }
  """
  @spec get_connection_status() :: [map()]
  @spec get_connection_status(RouterEx.RouterCore.connection_id()) :: map() | nil
  def get_connection_status do
    GenServer.call(__MODULE__, :get_all_connection_status)
  end

  def get_connection_status(connection_id) do
    GenServer.call(__MODULE__, {:get_connection_status, connection_id})
  end

  @doc """
  Checks if the system is healthy.

  Returns `true` if all connections are healthy, `false` otherwise.

  ## Examples

      iex> RouterEx.HealthMonitor.healthy?()
      true
  """
  @spec healthy?() :: boolean()
  def healthy? do
    %{status: status} = get_health()
    status == :healthy
  end

  @doc """
  Records activity for a connection.

  This is called internally by the router when messages are processed.
  """
  @spec record_activity(RouterEx.RouterCore.connection_id(), :send | :receive, pos_integer()) ::
          :ok
  def record_activity(connection_id, direction, count \\ 1) do
    GenServer.cast(__MODULE__, {:record_activity, connection_id, direction, count})
  end

  ## Server Callbacks

  @impl true
  def init(:ok) do
    # Schedule periodic health checks
    schedule_health_check()

    state = %State{
      start_time: System.monotonic_time(:millisecond),
      last_check: DateTime.utc_now(),
      connection_health: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    health = calculate_overall_health(state)
    {:reply, health, state}
  end

  @impl true
  def handle_call(:get_all_connection_status, _from, state) do
    statuses = get_all_statuses(state)
    {:reply, statuses, state}
  end

  @impl true
  def handle_call({:get_connection_status, connection_id}, _from, state) do
    status = get_status_for_connection(connection_id, state)
    {:reply, status, state}
  end

  @impl true
  def handle_cast({:record_activity, connection_id, direction, count}, state) do
    new_health =
      update_connection_activity(state.connection_health, connection_id, direction, count)

    {:noreply, %{state | connection_health: new_health}}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform health check
    new_state = perform_health_check(state)

    # Schedule next check
    schedule_health_check()

    {:noreply, new_state}
  end

  ## Private Functions

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @check_interval)
  end

  defp perform_health_check(state) do
    # Get current connections from RouterCore
    connections = RouterEx.RouterCore.get_connections()

    # Update health state with current connections
    new_health =
      connections
      |> Enum.reduce(state.connection_health, fn {conn_id, conn_info}, acc ->
        # Initialize or preserve existing health data
        existing =
          Map.get(acc, conn_id, %{
            first_seen: DateTime.utc_now(),
            last_activity: DateTime.utc_now(),
            messages_received: 0,
            messages_sent: 0,
            type: conn_info.type
          })

        # Check if connection is still alive
        alive = Process.alive?(conn_info.pid)

        Map.put(acc, conn_id, Map.put(existing, :alive, alive))
      end)

    # Remove connections that no longer exist
    current_conn_ids = MapSet.new(Map.keys(connections))

    new_health =
      Map.filter(new_health, fn {conn_id, _} -> MapSet.member?(current_conn_ids, conn_id) end)

    %{state | last_check: DateTime.utc_now(), connection_health: new_health}
  end

  defp calculate_overall_health(state) do
    now = System.monotonic_time(:millisecond)
    uptime = now - state.start_time

    connections = Map.keys(state.connection_health)
    total_connections = length(connections)

    {healthy, unhealthy} =
      Enum.reduce(connections, {0, 0}, fn conn_id, {h, u} ->
        if connection_healthy?(conn_id, state) do
          {h + 1, u}
        else
          {h, u + 1}
        end
      end)

    status =
      cond do
        total_connections == 0 -> :no_connections
        unhealthy == 0 -> :healthy
        healthy > unhealthy -> :degraded
        true -> :unhealthy
      end

    %{
      status: status,
      uptime: uptime,
      total_connections: total_connections,
      healthy_connections: healthy,
      unhealthy_connections: unhealthy,
      last_check: state.last_check
    }
  end

  defp connection_healthy?(connection_id, state) do
    case Map.get(state.connection_health, connection_id) do
      nil ->
        false

      health ->
        # Connection is healthy if:
        # 1. Process is alive
        # 2. Has recent activity (within threshold)
        alive = Map.get(health, :alive, false)
        last_activity = Map.get(health, :last_activity, DateTime.utc_now())

        time_since_activity =
          DateTime.diff(DateTime.utc_now(), last_activity, :millisecond)

        alive && time_since_activity < @unhealthy_threshold
    end
  end

  defp get_all_statuses(state) do
    state.connection_health
    |> Enum.map(fn {conn_id, health} ->
      build_status_map(conn_id, health, state)
    end)
    |> Enum.sort_by(& &1.connection_id)
  end

  defp get_status_for_connection(connection_id, state) do
    case Map.get(state.connection_health, connection_id) do
      nil -> nil
      health -> build_status_map(connection_id, health, state)
    end
  end

  defp build_status_map(connection_id, health, state) do
    healthy = connection_healthy?(connection_id, state)

    %{
      connection_id: connection_id,
      type: Map.get(health, :type, :unknown),
      status: if(healthy, do: :healthy, else: :unhealthy),
      alive: Map.get(health, :alive, false),
      first_seen: Map.get(health, :first_seen),
      last_activity: Map.get(health, :last_activity),
      messages_received: Map.get(health, :messages_received, 0),
      messages_sent: Map.get(health, :messages_sent, 0)
    }
  end

  defp update_connection_activity(health_map, connection_id, direction, count) do
    Map.update(
      health_map,
      connection_id,
      %{
        first_seen: DateTime.utc_now(),
        last_activity: DateTime.utc_now(),
        messages_received: if(direction == :receive, do: count, else: 0),
        messages_sent: if(direction == :send, do: count, else: 0),
        alive: true
      },
      fn existing ->
        existing
        |> Map.put(:last_activity, DateTime.utc_now())
        |> Map.update(:messages_received, count, fn current ->
          if direction == :receive, do: current + count, else: current
        end)
        |> Map.update(:messages_sent, count, fn current ->
          if direction == :send, do: current + count, else: current
        end)
      end
    )
  end
end
