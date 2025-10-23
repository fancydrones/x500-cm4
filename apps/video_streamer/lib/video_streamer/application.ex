defmodule VideoStreamer.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting VideoStreamer application")

    children = [
      # Telemetry supervisor for metrics
      VideoStreamer.Telemetry,

      # RTSP server - handles client connections
      {VideoStreamer.RTSP.Server, []},

      # Main streaming pipeline manager
      {VideoStreamer.PipelineManager, []}
    ]

    opts = [strategy: :one_for_one, name: VideoStreamer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
