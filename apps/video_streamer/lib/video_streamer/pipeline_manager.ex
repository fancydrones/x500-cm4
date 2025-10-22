defmodule VideoStreamer.PipelineManager do
  @moduledoc """
  Manages the lifecycle of the streaming pipeline.
  Handles start, stop, restart, and dynamic reconfiguration.
  """

  use GenServer
  require Logger

  alias VideoStreamer.Pipeline

  @type state :: %{
    pipeline: pid() | nil,
    config: map(),
    status: :stopped | :starting | :running | :error
  }

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_streaming do
    GenServer.call(__MODULE__, :start_streaming)
  end

  def stop_streaming do
    GenServer.call(__MODULE__, :stop_streaming)
  end

  def restart_streaming(new_config \\ nil, timeout \\ 15_000) do
    GenServer.call(__MODULE__, {:restart_streaming, new_config}, timeout)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Pipeline manager starting")

    state = %{
      pipeline: nil,
      config: load_config(),
      status: :stopped
    }

    # Auto-start streaming on init
    send(self(), :auto_start)

    {:ok, state}
  end

  @impl true
  def handle_call(:start_streaming, _from, %{status: :running} = state) do
    {:reply, {:ok, :already_running}, state}
  end

  def handle_call(:start_streaming, _from, state) do
    case start_pipeline(state.config) do
      {:ok, _supervisor_pid, pipeline_pid} ->
        new_state = %{state | pipeline: pipeline_pid, status: :running}
        Logger.info("Pipeline started successfully")
        {:reply, {:ok, :started}, new_state}

      {:error, reason} ->
        Logger.error("Failed to start pipeline: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | status: :error}}
    end
  end

  def handle_call(:stop_streaming, _from, %{pipeline: nil} = state) do
    {:reply, {:ok, :already_stopped}, state}
  end

  def handle_call(:stop_streaming, _from, state) do
    stop_pipeline(state.pipeline)
    new_state = %{state | pipeline: nil, status: :stopped}
    Logger.info("Pipeline stopped")
    {:reply, {:ok, :stopped}, new_state}
  end

  def handle_call({:restart_streaming, new_config}, _from, state) do
    # Stop existing pipeline
    if state.pipeline do
      Logger.info("Stopping existing pipeline #{inspect(state.pipeline)}")
      stop_pipeline(state.pipeline)
      # Pipeline is stopped synchronously with force, no need to sleep
    end

    # Update config if provided
    config = new_config || state.config

    Logger.info("Restarting pipeline with config: #{inspect(Map.take(config, [:client_ip, :client_port]))}")

    # Start new pipeline
    case start_pipeline(config) do
      {:ok, _supervisor_pid, pipeline_pid} ->
        new_state = %{state | pipeline: pipeline_pid, config: config, status: :running}
        Logger.info("Pipeline restarted successfully with PID #{inspect(pipeline_pid)}")
        {:reply, {:ok, :restarted}, new_state}

      {:error, reason} ->
        Logger.error("Failed to restart pipeline: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | status: :error}}
    end
  end

  def handle_call(:get_status, _from, state) do
    {:reply, %{status: state.status, config: state.config}, state}
  end

  @impl true
  def handle_info(:auto_start, state) do
    Logger.info("Auto-starting streaming pipeline")
    {:noreply, state}
    |> then(fn {:noreply, s} ->
      case start_pipeline(s.config) do
        {:ok, _supervisor_pid, pipeline_pid} -> {:noreply, %{s | pipeline: pipeline_pid, status: :running}}
        {:error, _} -> {:noreply, %{s | status: :error}}
      end
    end)
  end

  ## Private Functions

  defp start_pipeline(config) do
    # Extract client info if provided
    pipeline_opts = [
      client_ip: Map.get(config, :client_ip),
      client_port: Map.get(config, :client_port)
    ]

    Logger.info("Starting pipeline with opts: #{inspect(pipeline_opts)}")
    Membrane.Pipeline.start_link(Pipeline, pipeline_opts)
  end

  defp stop_pipeline(pipeline_pid) do
    # Use force to ensure pipeline terminates even if rpicam-vid doesn't exit cleanly
    # Increased timeout to 10 seconds to give camera time to shut down gracefully
    Membrane.Pipeline.terminate(pipeline_pid, timeout: 10_000, force?: true)
  end

  defp load_config do
    %{
      camera: Application.get_env(:video_streamer, :camera),
      rtsp: Application.get_env(:video_streamer, :rtsp),
      encoder: Application.get_env(:video_streamer, :encoder),
      # Client info will be added when RTSP PLAY is called
      client_ip: nil,
      client_port: nil
    }
  end
end
