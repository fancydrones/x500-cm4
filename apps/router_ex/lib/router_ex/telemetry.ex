defmodule RouterEx.Telemetry do
  @moduledoc """
  Telemetry setup for monitoring Router-Ex performance and behavior.

  This module sets up telemetry events and handlers for:
  - Message routing events
  - Connection events
  - Performance metrics
  - System health

  ## Telemetry Events

  ### Connection Events
  - `[:router_ex, :connection, :registered]` - New connection registered
  - `[:router_ex, :connection, :unregistered]` - Connection unregistered

  ### Message Events
  - `[:router_ex, :message, :routed]` - Message routed to destinations
  - `[:router_ex, :message, :filtered]` - Message filtered by rules

  ### Performance Events
  - `[:router_ex, :router_core, :routing_latency]` - Message routing latency
  - `[:router_ex, :endpoint, :send_latency]` - Endpoint send latency
  """

  use Supervisor
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller for VM metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    # Attach telemetry handlers
    :ok = attach_handlers()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp periodic_measurements do
    [
      # VM metrics
      {__MODULE__, :measure_memory, []},
      {__MODULE__, :measure_system, []}
    ]
  end

  defp attach_handlers do
    events = [
      [:router_ex, :connection, :registered],
      [:router_ex, :connection, :unregistered],
      [:router_ex, :message, :routed]
    ]

    :telemetry.attach_many(
      "router-ex-handler",
      events,
      &handle_event/4,
      nil
    )

    :ok
  end

  @doc """
  Handles telemetry events and logs them appropriately.
  """
  def handle_event(event, measurements, metadata, _config) do
    case event do
      [:router_ex, :connection, :registered] ->
        Logger.info(
          "Connection registered: #{inspect(metadata.connection_id)} (#{metadata.type})"
        )

      [:router_ex, :connection, :unregistered] ->
        Logger.info("Connection unregistered: #{inspect(metadata.connection_id)}")

      [:router_ex, :message, :routed] ->
        if measurements.filtered > 0 do
          Logger.debug(
            "Message routed from #{inspect(metadata.source)} to #{measurements.targets} destinations (#{measurements.filtered} filtered)"
          )
        else
          Logger.debug(
            "Message routed from #{inspect(metadata.source)} to #{measurements.targets} destinations"
          )
        end

      _ ->
        Logger.debug(
          "Telemetry event: #{inspect(event)}, measurements: #{inspect(measurements)}, metadata: #{inspect(metadata)}"
        )
    end
  end

  @doc """
  Measures current memory usage.
  """
  def measure_memory do
    memory = :erlang.memory()

    :telemetry.execute(
      [:router_ex, :vm, :memory],
      %{
        total: memory[:total],
        processes: memory[:processes],
        binary: memory[:binary],
        ets: memory[:ets]
      },
      %{}
    )
  end

  @doc """
  Measures system metrics.
  """
  def measure_system do
    :telemetry.execute(
      [:router_ex, :vm, :system],
      %{
        process_count: :erlang.system_info(:process_count),
        port_count: :erlang.system_info(:port_count),
        atom_count: :erlang.system_info(:atom_count)
      },
      %{}
    )
  end
end
