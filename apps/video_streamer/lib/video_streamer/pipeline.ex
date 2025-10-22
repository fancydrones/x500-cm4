defmodule VideoStreamer.Pipeline do
  @moduledoc """
  Main Membrane pipeline for video streaming.
  Captures video from Raspberry Pi camera, encodes to H.264,
  and outputs RTP packets for RTSP streaming.
  """

  use Membrane.Pipeline

  require Membrane.Logger

  @impl true
  def handle_init(_ctx, _opts) do
    camera_config = Application.get_env(:video_streamer, :camera)

    spec = [
      child(:camera_source, %Membrane.Rpicam.Source{
        width: camera_config[:width],
        height: camera_config[:height],
        framerate: {camera_config[:framerate], 1},
        verbose: Keyword.get(camera_config, :verbose, false)
      })
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_alignment: :nalu,
        generate_best_effort_timestamps: %{framerate: {camera_config[:framerate], 1}}
      })
      |> child(:rtp_payloader, Membrane.RTP.H264.Payloader)
      # Temporary sink for Phase 1 testing - will be replaced with RTSP output in Phase 2
      |> child(:fake_sink, Membrane.Fake.Sink.Buffers)
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification(notification, element, _ctx, state) do
    Membrane.Logger.debug("Notification from #{inspect(element)}: #{inspect(notification)}")
    {[], state}
  end
end
