defmodule VideoStreamer.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting VideoStreamer application")

    # In test environment, only start telemetry to avoid camera initialization errors
    # This makes test output cleaner on development machines without camera hardware
    children =
      case Mix.env() do
        :test ->
          [
            # Only start telemetry in test mode
            VideoStreamer.Telemetry
          ]

        _ ->
          [
            # Telemetry supervisor for metrics
            VideoStreamer.Telemetry,

            # RTSP server - handles client connections
            {VideoStreamer.RTSP.Server, []},

            # Main streaming pipeline manager
            {VideoStreamer.PipelineManager, []}
          ]
      end

    opts = [strategy: :one_for_one, name: VideoStreamer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
