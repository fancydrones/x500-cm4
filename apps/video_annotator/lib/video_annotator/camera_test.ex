defmodule VideoAnnotator.CameraTest do
  @moduledoc """
  Helper to test different cameras and save sample frames.
  """

  require Logger

  @doc """
  Test a specific camera and save a sample frame.

  ## Example

      VideoAnnotator.CameraTest.test_camera("1")
      VideoAnnotator.CameraTest.test_camera("3")
  """
  def test_camera(camera_id) do
    Logger.info("Testing camera #{camera_id}...")

    {:ok, _supervisor_pid, pipeline_pid} =
      Membrane.Pipeline.start_link(VideoAnnotator.Pipeline,
        camera: camera_id,
        model_path: "priv/models/yolox_nano.onnx",
        classes_path: "priv/models/coco_classes.json",
        output_path: "priv/output/test.h264",
        preview: false
      )

    Logger.info("Pipeline started, waiting 3 seconds for frames...")
    Process.sleep(3000)

    Logger.info("Stopping pipeline...")
    Membrane.Pipeline.terminate(pipeline_pid)

    # Check if frames were saved
    case File.ls("priv/debug_frames") do
      {:ok, files} ->
        latest = files |> Enum.sort() |> List.last()
        Logger.info("Latest frame: priv/debug_frames/#{latest}")
        {:ok, "priv/debug_frames/#{latest}"}

      {:error, _} ->
        {:error, "No frames captured"}
    end
  end

  @doc """
  List all available cameras (requires ffmpeg).
  """
  def list_cameras do
    Logger.info("Available cameras:")
    Logger.info("  [0] OBS Virtual Camera")
    Logger.info("  [1] FaceTime HD Camera")
    Logger.info("  [2] Ri17P Desk View Camera")
    Logger.info("  [3] Ri17P Camera")

    :ok
  end
end
