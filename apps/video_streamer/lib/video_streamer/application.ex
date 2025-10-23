defmodule VideoStreamer.Application do
  @moduledoc false

  use Application

  require Logger

  # Compile-time configuration - determines which children to start
  # In test environment, only start telemetry to avoid camera initialization errors
  @children (if Application.compile_env(:video_streamer, :env) == :test do
               [
                 # Only start telemetry in test mode
                 VideoStreamer.Telemetry
               ]
             else
               [
                 # Telemetry supervisor for metrics
                 VideoStreamer.Telemetry,

                 # RTSP server - handles client connections
                 {VideoStreamer.RTSP.Server, []},

                 # Main streaming pipeline manager
                 {VideoStreamer.PipelineManager, []}
               ]
             end)

  @impl true
  def start(_type, _args) do
    Logger.info("Starting VideoStreamer application")

    opts = [strategy: :one_for_one, name: VideoStreamer.Supervisor]
    Supervisor.start_link(@children, opts)
  end
end
