defmodule VideoAnnotator.InferenceTest do
  @moduledoc """
  Quick test module to verify YOLOX model loading and basic inference.
  This is for Phase 0 development testing.
  """

  require Logger

  @doc """
  Load the YOLOX-Nano model and test basic inference.

  ## Example

      iex> VideoAnnotator.InferenceTest.run()
      {:ok, "Model loaded successfully"}
  """
  def run do
    Logger.info("Starting YOLOX inference test...")

    # Step 1: Load the model
    Logger.info("Loading YOLOX-Nano model...")
    model_path = Path.expand("../../priv/models/yolox_nano.onnx", __DIR__)
    classes_path = Path.expand("../../priv/models/coco_classes.json", __DIR__)

    unless File.exists?(model_path) do
      {:error, "Model file not found: #{model_path}"}
    else
      unless File.exists?(classes_path) do
        {:error, "Classes file not found: #{classes_path}"}
      else
        try do
          # Load class names
          {:ok, classes_json} = File.read(classes_path)
          classes = Jason.decode!(classes_json)

          Logger.info("Loading model from: #{model_path}")
          Logger.info("Classes: #{length(classes)} COCO classes loaded")

          # Initialize YOLOX model
          model = YOLO.load(
            model_path: model_path,
            classes_path: classes_path,
            model_impl: YOLO.Models.YOLOX
          )

          Logger.info("Model loaded successfully!")
          Logger.info("Model info: #{inspect(model)}")

          {:ok, "Model loaded successfully with #{length(classes)} classes"}
        rescue
          error ->
            Logger.error("Failed to load model: #{inspect(error)}")
            {:error, Exception.message(error)}
        end
      end
    end
  end

  @doc """
  Test inference on a sample image and save annotated output.
  """
  def test_image(image_path, output_path \\ nil) do
    Logger.info("Testing inference on image: #{image_path}")

    unless File.exists?(image_path) do
      {:error, "Image file not found: #{image_path}"}
    else
      model_path = Path.expand("../../priv/models/yolox_nano.onnx", __DIR__)

      try do
        # Load model
        classes_path = Path.expand("../../priv/models/coco_classes.json", __DIR__)

        model = YOLO.load(
          model_path: model_path,
          classes_path: classes_path,
          model_impl: YOLO.Models.YOLOX
        )

        # Load image with Evision
        Logger.info("Loading image with Evision...")
        image = Evision.imread(image_path)
        Logger.info("Image shape: #{inspect(Evision.Mat.shape(image))}")

        # Run inference
        Logger.info("Running inference...")
        predictions = YOLO.detect(model, image)

        Logger.info("Predictions count: #{length(predictions)}")
        Logger.info("Predictions: #{inspect(predictions, limit: 10)}")

        # Draw bounding boxes if output path specified
        if output_path do
          annotated_image = draw_detections(image, predictions, classes_path)
          Evision.imwrite(output_path, annotated_image)
          Logger.info("Saved annotated image to: #{output_path}")
        end

        {:ok, predictions}
      rescue
        error ->
          Logger.error("Inference failed: #{inspect(error)}")
          {:error, Exception.message(error)}
      end
    end
  end

  # Private helper to draw bounding boxes on image
  defp draw_detections(image, predictions, classes_path) do
    # Load class names
    {:ok, classes_json} = File.read(classes_path)
    classes_list = Jason.decode!(classes_json)

    # Draw each detection
    Enum.reduce(predictions, image, fn [cx, cy, w, h, conf, class_id], img ->
      class_idx = trunc(class_id)
      class_name = Enum.at(classes_list, class_idx, "unknown")
      confidence = Float.round(conf * 100, 1)

      # Convert from center coordinates to top-left corner
      x1 = trunc(cx - w / 2)
      y1 = trunc(cy - h / 2)
      x2 = trunc(cx + w / 2)
      y2 = trunc(cy + h / 2)

      # Draw rectangle (green color, thickness 2)
      img = Evision.rectangle(img, {x1, y1}, {x2, y2}, {0, 255, 0}, thickness: 2)

      # Draw label background (filled rectangle)
      label = "#{class_name} #{confidence}%"
      text_size = Evision.getTextSize(label, Evision.Constant.cv_FONT_HERSHEY_SIMPLEX(), 0.5, 1)
      {text_w, text_h} = elem(text_size, 0)

      img = Evision.rectangle(
        img,
        {x1, y1 - text_h - 8},
        {x1 + text_w + 4, y1},
        {0, 255, 0},
        thickness: -1
      )

      # Draw label text (black on green background)
      Evision.putText(
        img,
        label,
        {x1 + 2, y1 - 4},
        Evision.Constant.cv_FONT_HERSHEY_SIMPLEX(),
        0.5,
        {0, 0, 0},
        thickness: 1
      )
    end)
  end
end
