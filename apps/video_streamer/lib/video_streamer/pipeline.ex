defmodule VideoStreamer.Pipeline do
  @moduledoc """
  Main Membrane pipeline for video streaming.
  Captures video from Raspberry Pi camera, encodes to H.264,
  and outputs RTP packets for RTSP streaming.

  Phase 3: Multi-client support using Membrane.Tee to dynamically
  create output branches for each connected client.
  """

  use Membrane.Pipeline

  require Membrane.Logger

  @impl true
  def handle_init(_ctx, _opts) do
    camera_config = Application.get_env(:video_streamer, :camera)

    Membrane.Logger.info("Pipeline init - multi-client mode with Tee")

    # Build pipeline spec with Tee for multi-client support
    spec = build_pipeline_spec(camera_config)

    # Track active clients: %{client_id => %{ip: ip, port: port}}
    {[spec: spec], %{clients: %{}}}
  end

  @impl true
  def handle_child_notification(notification, element, _ctx, state) do
    Membrane.Logger.debug("Notification from #{inspect(element)}: #{inspect(notification)}")
    {[], state}
  end

  @impl true
  def handle_child_pad_removed(child, pad, _ctx, state) do
    Membrane.Logger.debug("Pad #{inspect(pad)} removed from child #{inspect(child)}")
    {[], state}
  end

  @impl true
  def handle_child_terminated(child, _ctx, state) do
    Membrane.Logger.warning("Child #{inspect(child)} terminated")
    {[], state}
  end

  @impl true
  def handle_info({:add_client, client_id, client_ip, client_port}, _ctx, state) do
    Membrane.Logger.info("Adding client #{client_id}: #{client_ip}:#{client_port}")

    if Map.has_key?(state.clients, client_id) do
      Membrane.Logger.warning("Client #{client_id} already exists, ignoring")
      {[], state}
    else
      # Generate unique SSRC for this client
      ssrc = :erlang.phash2({client_id, :os.system_time(:millisecond)}, 0xFFFFFFFF)

      # Create a new branch from the Tee for this client
      spec = [
        get_child(:tee)
        |> child({:rtp_stream, client_id}, %Membrane.RTP.StreamSendBin{
          payloader: Membrane.RTP.H264.Payloader,
          payload_type: 96,
          ssrc: ssrc,
          clock_rate: 90_000,
          rtcp_report_interval: nil
        })
        |> child({:rtp_sink, client_id}, %VideoStreamer.RTP.UDPSink{
          client_ip: client_ip,
          client_port: client_port
        })
      ]

      new_clients = Map.put(state.clients, client_id, %{ip: client_ip, port: client_port, ssrc: ssrc})

      Membrane.Logger.info("Client #{client_id} added with SSRC #{ssrc}. Active clients: #{map_size(new_clients)}")

      {[spec: spec], %{state | clients: new_clients}}
    end
  end

  @impl true
  def handle_info({:remove_client, client_id}, _ctx, state) do
    Membrane.Logger.info("Removing client #{client_id}")

    if Map.has_key?(state.clients, client_id) do
      # Remove the client's branch from the pipeline
      actions = [
        remove_children: [
          {:rtp_sink, client_id},
          {:rtp_stream, client_id}
        ]
      ]

      new_clients = Map.delete(state.clients, client_id)

      Membrane.Logger.info("Client #{client_id} removed. Active clients: #{map_size(new_clients)}")

      {actions, %{state | clients: new_clients}}
    else
      Membrane.Logger.warning("Client #{client_id} not found, ignoring")
      {[], state}
    end
  end

  ## Private Functions

  defp build_pipeline_spec(camera_config) do
    # Build base pipeline with Tee for multi-client support
    # Using Tee.Parallel which allows dynamic output pads without requiring master pad
    [
      child(:camera_source, %Membrane.Rpicam.Source{
        width: camera_config[:width],
        height: camera_config[:height],
        framerate: {camera_config[:framerate], 1},
        verbose: Keyword.get(camera_config, :verbose, false)
      })
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_alignment: :nalu,
        generate_best_effort_timestamps: %{framerate: {camera_config[:framerate], 1}},
        repeat_parameter_sets: true
      })
      |> child(:tee, Membrane.Tee.Parallel)
    ]
  end
end
