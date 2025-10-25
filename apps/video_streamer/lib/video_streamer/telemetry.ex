defmodule VideoStreamer.Telemetry do
  @moduledoc """
  Telemetry setup for monitoring pipeline performance.
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
      {VideoStreamer.Telemetry, :measure_memory, []},
      {VideoStreamer.Telemetry, :measure_cpu, []}
    ]
  end

  defp attach_handlers do
    events = [
      [:membrane, :pipeline, :init],
      [:membrane, :pipeline, :crash],
      [:membrane, :element, :init],
      [:membrane, :element, :crash]
    ]

    :telemetry.attach_many(
      "video-streamer-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  def handle_event(event, measurements, metadata, _config) do
    Logger.debug(
      "Telemetry event: #{inspect(event)}, measurements: #{inspect(measurements)}, metadata: #{inspect(metadata)}"
    )
  end

  def measure_memory do
    memory = :erlang.memory()

    %{
      total: memory[:total],
      processes: memory[:processes],
      binary: memory[:binary]
    }
  end

  def measure_cpu do
    # CPU utilization measurements
    %{}
  end
end
