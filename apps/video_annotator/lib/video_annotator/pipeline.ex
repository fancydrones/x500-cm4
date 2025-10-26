defmodule VideoAnnotator.Pipeline do
  @moduledoc """
  Membrane pipeline for webcam capture with real-time YOLO object detection.

  This pipeline:
  1. Captures video from webcam using Membrane.CameraCapture
  2. Runs YOLO detection on each frame
  3. Annotates frames with bounding boxes
  4. Saves to file or displays output
  """
  use Membrane.Pipeline

  require Logger

  @impl true
  def handle_init(_ctx, opts) do
    camera = opts[:camera] || "1"
    model_path = opts[:model_path] || "priv/models/yolox_nano.onnx"
    classes_path = opts[:classes_path] || "priv/models/coco_classes.json"
    output_path = opts[:output_path] || "priv/output/webcam_annotated.h264"
    preview = opts[:preview] || false
    preview_interval = opts[:preview_interval] || 10

    Logger.info("Starting VideoAnnotator Pipeline")
    Logger.info("Camera: #{camera}")
    Logger.info("Model: #{model_path}")
    Logger.info("Output: #{output_path}")
    Logger.info("Preview: #{preview}")

    # Ensure output directory exists
    output_dir = Path.dirname(output_path)
    File.mkdir_p!(output_dir)

    spec =
      # Webcam source - captures raw video frames at 30fps
      # Supported resolutions: 1920x1080, 1280x720, 640x480, 1552x1552 @ 15-30fps
      child(:camera, %Membrane.CameraCapture{
        device: camera,
        framerate: 30
      })
      # Use minimal toilet capacity to drop old frames automatically
      # This ensures YoloDetector always gets the latest frame and processes as fast as it can
      # Adapts automatically to CPU load - faster when CPU is free, slower when busy
      |> via_in(:input, toilet_capacity: 1)
      |> child(:yolo_detector, %VideoAnnotator.YoloDetector{
        model_path: model_path,
        classes_path: classes_path,
        preview: preview,
        preview_dir: "priv/preview",
        preview_interval: preview_interval
      })
      |> child(:sink, Membrane.Fake.Sink.Buffers)

    {[spec: spec], %{output_path: output_path, preview: preview}}
  end

  @impl true
  def handle_child_notification({:buffers, buffers}, :sink, _ctx, state) do
    # Log received buffers (for debugging)
    Logger.debug("Received #{length(buffers)} buffers from sink")
    {[], state}
  end

  @impl true
  def handle_child_notification(notification, child, _ctx, state) do
    Logger.debug("Notification from #{inspect(child)}: #{inspect(notification)}")
    {[], state}
  end
end
