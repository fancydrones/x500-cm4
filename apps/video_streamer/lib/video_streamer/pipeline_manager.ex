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

  def restart_streaming(new_config \\ nil) do
    GenServer.call(__MODULE__, {:restart_streaming, new_config})
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
    if state.pipeline, do: stop_pipeline(state.pipeline)

    # Update config if provided
    config = new_config || state.config

    # Start new pipeline
    case start_pipeline(config) do
      {:ok, _supervisor_pid, pipeline_pid} ->
        new_state = %{state | pipeline: pipeline_pid, config: config, status: :running}
        Logger.info("Pipeline restarted with new config")
        {:reply, {:ok, :restarted}, new_state}

      {:error, reason} ->
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
    Membrane.Pipeline.start_link(Pipeline, config)
  end

  defp stop_pipeline(pipeline_pid) do
    Membrane.Pipeline.terminate(pipeline_pid)
  end

  defp load_config do
    %{
      camera: Application.get_env(:video_streamer, :camera),
      rtsp: Application.get_env(:video_streamer, :rtsp),
      encoder: Application.get_env(:video_streamer, :encoder)
    }
  end
end
