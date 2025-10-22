defmodule VideoStreamer.Pipeline do
  @moduledoc """
  Main Membrane pipeline for video streaming.
  Captures video from Raspberry Pi camera, encodes to H.264,
  and outputs RTP packets for RTSP streaming.
  """

  use Membrane.Pipeline

  require Membrane.Logger

  @impl true
  def handle_init(_ctx, opts) do
    camera_config = Application.get_env(:video_streamer, :camera)

    # Check if client info is provided (for RTP streaming)
    client_ip = opts[:client_ip]
    client_port = opts[:client_port]

    Membrane.Logger.info("Pipeline init with client_ip=#{inspect(client_ip)}, client_port=#{inspect(client_port)}")

    # Build pipeline spec
    spec = build_pipeline_spec(camera_config, client_ip, client_port)

    {[spec: spec], %{client_ip: client_ip, client_port: client_port}}
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

  ## Private Functions

  defp build_pipeline_spec(camera_config, client_ip, client_port) do
    base_spec = [
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
      |> child(:rtp_payloader, Membrane.RTP.H264.Payloader)
    ]

    # Add appropriate sink based on whether we have client info
    if client_ip && client_port do
      Membrane.Logger.info("Pipeline configured for RTP streaming to #{client_ip}:#{client_port}")

      base_spec ++
        [
          get_child(:rtp_payloader)
          |> child(:rtp_sink, %VideoStreamer.RTP.UDPSink{
            client_ip: client_ip,
            client_port: client_port
          })
        ]
    else
      Membrane.Logger.info("Pipeline configured with fake sink (no client)")

      base_spec ++
        [
          get_child(:rtp_payloader)
          |> child(:fake_sink, Membrane.Fake.Sink.Buffers)
        ]
    end
  end
end
