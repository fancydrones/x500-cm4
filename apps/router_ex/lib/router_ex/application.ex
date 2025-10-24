defmodule RouterEx.Application do
  @moduledoc """
  Main application module for Router-Ex.

  Router-Ex is an Elixir-based MAVLink message router that intelligently
  routes messages between serial, UDP, and TCP connections.

  The application supervision tree (in start order):
  - Telemetry: Metrics and monitoring
  - RouterCore: Core message routing logic
  - HealthMonitor: Connection health monitoring
  - Endpoint.Supervisor: Manages connection endpoints
  - ConfigManager: Manages router configuration and starts endpoints
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Router-Ex application")

    children = [
      # Telemetry setup
      RouterEx.Telemetry,

      # Router core (message routing logic)
      RouterEx.RouterCore,

      # Health monitor (connection health monitoring)
      RouterEx.HealthMonitor,

      # Connection supervisor (manages all endpoint connections)
      # IMPORTANT: Must start before ConfigManager since ConfigManager starts endpoints
      {DynamicSupervisor, name: RouterEx.Endpoint.Supervisor, strategy: :one_for_one},

      # Configuration manager
      # Starts last because it needs Endpoint.Supervisor to be ready
      RouterEx.ConfigManager
    ]

    opts = [strategy: :one_for_one, name: RouterEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
