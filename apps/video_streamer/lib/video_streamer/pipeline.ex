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
    encoder_config = Application.get_env(:video_streamer, :encoder, [])
    rtsp_config = Application.get_env(:video_streamer, :rtsp, [])

    Membrane.Logger.info("=== Video Streamer Configuration ===")

    # Log camera settings
    Membrane.Logger.info("Camera Settings:")
    Membrane.Logger.info("  Resolution: #{camera_config[:width]}x#{camera_config[:height]}")
    Membrane.Logger.info("  Framerate: #{camera_config[:framerate]} fps")
    Membrane.Logger.info("  H-Flip: #{camera_config[:hflip]} (#{get_config_source("CAMERA_HFLIP", camera_config[:hflip], false)})")
    Membrane.Logger.info("  V-Flip: #{camera_config[:vflip]} (#{get_config_source("CAMERA_VFLIP", camera_config[:vflip], false)})")

    # Log encoder settings
    Membrane.Logger.info("Encoder Settings:")
    Membrane.Logger.info("  Profile: #{Keyword.get(encoder_config, :profile, :main)} (#{get_config_source("H264_PROFILE", Keyword.get(encoder_config, :profile), :main)})")
    Membrane.Logger.info("  Level: #{Keyword.get(encoder_config, :level, "4.1")} (#{get_config_source("H264_LEVEL", Keyword.get(encoder_config, :level), "4.1")})")
    Membrane.Logger.info("  Bitrate: #{format_bitrate(Keyword.get(encoder_config, :bitrate, :auto))} (#{get_config_source("H264_BITRATE", Keyword.get(encoder_config, :bitrate), :auto)})")
    Membrane.Logger.info("  Keyframe Interval: #{Keyword.get(encoder_config, :keyframe_interval, 30)} frames (#{get_config_source("KEYFRAME_INTERVAL", Keyword.get(encoder_config, :keyframe_interval), 30)})")
    Membrane.Logger.info("  Inline Headers: #{Keyword.get(encoder_config, :inline_headers, true)} (#{get_config_source("H264_INLINE_HEADERS", Keyword.get(encoder_config, :inline_headers), true)})")
    Membrane.Logger.info("  Flush: #{Keyword.get(encoder_config, :flush, false)} (#{get_config_source("H264_FLUSH", Keyword.get(encoder_config, :flush), false)})")
    Membrane.Logger.info("  Low Latency: #{Keyword.get(encoder_config, :low_latency, true)} (#{get_config_source("H264_LOW_LATENCY", Keyword.get(encoder_config, :low_latency), true)})")
    Membrane.Logger.info("  Denoise: #{Keyword.get(encoder_config, :denoise, :cdn_off)} (#{get_config_source("H264_DENOISE", Keyword.get(encoder_config, :denoise), :cdn_off)})")
    Membrane.Logger.info("  Buffer Count: #{Keyword.get(encoder_config, :buffer_count, 6)} (#{get_config_source("H264_BUFFER_COUNT", Keyword.get(encoder_config, :buffer_count), 6)})")

    # Log RTSP settings
    Membrane.Logger.info("RTSP Settings:")
    Membrane.Logger.info("  Port: #{Keyword.get(rtsp_config, :port, 8554)}")
    Membrane.Logger.info("  Path: #{Keyword.get(rtsp_config, :path, "/video")}")

    Membrane.Logger.info("=== Configuration Complete ===")

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
          payloader: %Membrane.RTP.H264.Payloader{max_payload_size: 1200},
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

      new_clients =
        Map.put(state.clients, client_id, %{ip: client_ip, port: client_port, ssrc: ssrc})

      Membrane.Logger.info(
        "Client #{client_id} added with SSRC #{ssrc}. Active clients: #{map_size(new_clients)}"
      )

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

      Membrane.Logger.info(
        "Client #{client_id} removed. Active clients: #{map_size(new_clients)}"
      )

      {actions, %{state | clients: new_clients}}
    else
      Membrane.Logger.warning("Client #{client_id} not found, ignoring")
      {[], state}
    end
  end

  ## Private Functions

  defp build_pipeline_spec(camera_config) do
    # Get encoder config
    encoder_config = Application.get_env(:video_streamer, :encoder, [])

    # Build base pipeline with Tee for multi-client support
    # Using Tee.Parallel which allows dynamic output pads without requiring master pad
    [
      child(:camera_source, %Membrane.Rpicam.Source{
        width: camera_config[:width],
        height: camera_config[:height],
        framerate: {camera_config[:framerate], 1},
        verbose: Keyword.get(camera_config, :verbose, false),
        profile: Keyword.get(encoder_config, :profile, :main),
        level: Keyword.get(encoder_config, :level, "4.1"),
        bitrate: Keyword.get(encoder_config, :bitrate, :auto),
        keyframe_interval: Keyword.get(encoder_config, :keyframe_interval, 30),
        inline_headers: Keyword.get(encoder_config, :inline_headers, true),
        flush: Keyword.get(encoder_config, :flush, false),
        low_latency: Keyword.get(encoder_config, :low_latency, true),
        denoise: Keyword.get(encoder_config, :denoise, :cdn_off),
        buffer_count: Keyword.get(encoder_config, :buffer_count, 6),
        hflip: Keyword.get(camera_config, :hflip, false),
        vflip: Keyword.get(camera_config, :vflip, false)
      })
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_alignment: :nalu,
        generate_best_effort_timestamps: %{framerate: {camera_config[:framerate], 1}},
        repeat_parameter_sets: false
      })
      |> child(:tee, Membrane.Tee.Parallel)
    ]
  end

  ## Helper functions for configuration logging

  defp get_config_source(env_var, current_value, default_value) do
    env_value = System.get_env(env_var)

    cond do
      env_value != nil ->
        "env: #{env_var}=#{env_value}"

      current_value == default_value ->
        "default"

      true ->
        "config"
    end
  end

  defp format_bitrate(:auto), do: "auto"
  defp format_bitrate(bitrate) when is_integer(bitrate) do
    mbps = bitrate / 1_000_000
    "#{bitrate} bps (#{Float.round(mbps, 1)} Mbps)"
  end
end
