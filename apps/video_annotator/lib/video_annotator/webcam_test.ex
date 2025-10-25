defmodule VideoAnnotator.WebcamTest do
  @moduledoc """
  Helper module to test webcam capture with YOLO detection.
  """

  require Logger

  @doc """
  Start the webcam pipeline for testing.

  ## Options
    * `:duration` - How long to run in seconds (default: 10)
    * `:camera` - Camera device name or ID (default: "FaceTime HD Camera")
                  Can be camera name: "FaceTime HD Camera", "OBS Virtual Camera"
                  Or device ID: "0" = OBS Virtual Camera, "1" = FaceTime HD Camera
    * `:model_path` - Path to YOLOX model
    * `:classes_path` - Path to classes JSON
    * `:output_path` - Path for output video file
    * `:preview` - Show live preview with annotations (default: false)

  ## Example

      VideoAnnotator.WebcamTest.start(duration: 30, camera: "FaceTime HD Camera")
      VideoAnnotator.WebcamTest.start(camera: "FaceTime HD Camera", preview: true)
  """
  def start(opts \\ []) do
    duration = Keyword.get(opts, :duration, 10)
    camera = Keyword.get(opts, :camera, "FaceTime HD Camera")
    model_path = Keyword.get(opts, :model_path, "priv/models/yolox_nano.onnx")
    classes_path = Keyword.get(opts, :classes_path, "priv/models/coco_classes.json")
    output_path = Keyword.get(opts, :output_path, "priv/output/webcam_annotated.h264")
    preview = Keyword.get(opts, :preview, false)

    # Resolve paths relative to app directory
    model_path = Path.expand(model_path)
    classes_path = Path.expand(classes_path)
    output_path = Path.expand(output_path)

    Logger.info("Starting webcam test for #{duration} seconds...")
    Logger.info("Camera: #{camera}")
    Logger.info("Model: #{model_path}")
    Logger.info("Classes: #{classes_path}")
    Logger.info("Preview: #{preview}")

    unless File.exists?(model_path) do
      Logger.error("Model file not found: #{model_path}")
      {:error, :model_not_found}
    else
      unless File.exists?(classes_path) do
        Logger.error("Classes file not found: #{classes_path}")
        {:error, :classes_not_found}
      else
        # Start the pipeline (automatically plays)
        {:ok, _supervisor_pid, pipeline_pid} =
          Membrane.Pipeline.start_link(VideoAnnotator.Pipeline,
            camera: camera,
            model_path: model_path,
            classes_path: classes_path,
            output_path: output_path,
            preview: preview
          )

        Logger.info("Pipeline started: #{inspect(pipeline_pid)}")
        Logger.info("Recording for #{duration} seconds...")
        Logger.info("Press Ctrl+C to stop early")

        # Wait for specified duration
        Process.sleep(duration * 1000)

        # Stop the pipeline
        Logger.info("Stopping pipeline...")
        Membrane.Pipeline.terminate(pipeline_pid)

        Logger.info("Test complete!")
        {:ok, :completed}
      end
    end
  end
end
