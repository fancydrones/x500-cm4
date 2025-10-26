defmodule VideoAnnotator.YoloDetector do
  @moduledoc """
  Membrane Filter that performs YOLO object detection on raw video frames.

  This filter receives raw video frames (BGR/RGB), runs YOLO inference,
  and outputs the same frames with detection metadata attached.
  """
  use Membrane.Filter

  require Logger

  def_input_pad :input,
    accepted_format: Membrane.RawVideo,
    flow_control: :auto

  def_output_pad :output,
    accepted_format: Membrane.RawVideo,
    flow_control: :auto

  def_options model_path: [
                spec: String.t(),
                description: "Path to YOLOX ONNX model file"
              ],
              classes_path: [
                spec: String.t(),
                description: "Path to COCO classes JSON file"
              ],
              preview: [
                spec: boolean(),
                description: "Enable live preview with annotations",
                default: false
              ],
              preview_dir: [
                spec: String.t() | nil,
                description: "Directory to save preview frames",
                default: nil
              ],
              preview_interval: [
                spec: pos_integer(),
                description: "Save preview every N frames (default: 10 = ~3 FPS at 30 FPS input)",
                default: 10
              ]

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      model_path: opts.model_path,
      classes_path: opts.classes_path,
      preview: opts.preview,
      preview_dir: opts.preview_dir,
      preview_interval: opts.preview_interval,
      model: nil,
      classes: nil,
      frame_count: 0,
      total_inference_time: 0
    }

    # Create preview directory if needed
    if opts.preview && opts.preview_dir do
      File.mkdir_p!(opts.preview_dir)
      Logger.info("Preview frames will be saved to: #{opts.preview_dir}")
    end

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    # Load YOLO model when pipeline starts
    Logger.info("Loading YOLO model from: #{state.model_path}")

    # Try to use CoreML on macOS for hardware acceleration, fall back to CPU
    execution_providers = get_execution_providers()
    Logger.info("Using execution providers: #{inspect(execution_providers)}")

    model = YOLO.load(
      model_path: state.model_path,
      classes_path: state.classes_path,
      model_impl: YOLO.Models.YOLOX,
      execution_providers: execution_providers
    )

    # Load class names
    {:ok, classes_json} = File.read(state.classes_path)
    classes = Jason.decode!(classes_json)

    Logger.info("YOLO model loaded successfully with #{length(classes)} classes")

    state = %{state | model: model, classes: classes}
    {[], state}
  end

  # Get optimal execution providers based on platform
  defp get_execution_providers do
    case :os.type() do
      {:unix, :darwin} ->
        # On macOS, try CoreML first, then CPU
        [:coreml, :cpu]

      _ ->
        # On other platforms, use CPU
        [:cpu]
    end
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    # Extract raw frame data and stream format
    %Membrane.Buffer{payload: raw_frame} = buffer

    # Get stream format from context
    stream_format = ctx.pads.input.stream_format

    # Run inference
    start_time = System.monotonic_time(:millisecond)
    {detections, rgb_mat} = run_detection(raw_frame, stream_format, state.model, state.frame_count)
    inference_time = System.monotonic_time(:millisecond) - start_time

    # Annotate the frame with bounding boxes
    annotated_mat =
      if length(detections) > 0 do
        draw_detections(rgb_mat, detections, state.classes)
      else
        rgb_mat
      end

    # Save annotated preview if enabled (only every N frames to avoid I/O bottleneck)
    if state.preview && state.preview_dir && rem(state.frame_count, state.preview_interval) == 0 do
      save_preview_frame(annotated_mat, state.preview_dir, state.frame_count, length(detections))
    end

    # Update statistics
    frame_count = state.frame_count + 1
    total_time = state.total_inference_time + inference_time
    avg_time = total_time / frame_count
    fps = 1000.0 / avg_time

    if rem(frame_count, 30) == 0 do
      Logger.info(
        "Frame #{frame_count}: #{length(detections)} detections, " <>
          "#{inference_time}ms inference, avg #{Float.round(avg_time, 1)}ms (#{Float.round(fps, 1)} FPS)"
      )
    end

    # Pass through the original buffer with detection metadata
    buffer = %{
      buffer
      | metadata: Map.put(buffer.metadata || %{}, :detections, detections)
    }

    state = %{
      state
      | frame_count: frame_count,
        total_inference_time: total_time
    }

    {[buffer: {:output, buffer}], state}
  end

  # Private helper to run YOLO detection
  defp run_detection(raw_frame, stream_format, model, frame_count) do
    # Extract format information
    %Membrane.RawVideo{
      width: width,
      height: height,
      pixel_format: pixel_format
    } = stream_format

    # Convert from camera format to RGB for YOLO
    # Evision.Mat.from_binary expects: (binary, type, rows, cols, channels)
    rgb_mat =
      case pixel_format do
        :NV12 ->
          # NV12 is YUV420 semi-planar format: Y plane + interleaved UV plane
          # NV12 needs exactly height * 1.5 rows, but frame may be padded
          # Extract just the bytes we need (no padding)
          expected_size = width * div(height * 3, 2)
          cropped_frame = binary_part(raw_frame, 0, expected_size)

          nv12_mat = Evision.Mat.from_binary(cropped_frame, :u8, div(height * 3, 2), width, 1)
          Evision.cvtColor(nv12_mat, Evision.Constant.cv_COLOR_YUV2RGB_NV12())

        :I420 ->
          # I420 is YUV420 planar format
          i420_mat = Evision.Mat.from_binary(raw_frame, :u8, div(height * 3, 2), width, 1)
          Evision.cvtColor(i420_mat, Evision.Constant.cv_COLOR_YUV2RGB_I420())

        :RGB ->
          # Already RGB
          Evision.Mat.from_binary(raw_frame, :u8, height, width, 3)

        :BGR ->
          # BGR needs conversion to RGB
          bgr_mat = Evision.Mat.from_binary(raw_frame, :u8, height, width, 3)
          Evision.cvtColor(bgr_mat, Evision.Constant.cv_COLOR_BGR2RGB())

        other ->
          Logger.error("Unsupported pixel format: #{inspect(other)}")
          raise "Unsupported pixel format: #{inspect(other)}"
      end

    # Run YOLO detection
    detections = YOLO.detect(model, rgb_mat)

    {detections, rgb_mat}
  rescue
    error ->
      Logger.error("Detection failed: #{inspect(error)}")
      Logger.error("Stream format: #{inspect(stream_format)}")
      Logger.error("Frame size: #{byte_size(raw_frame)} bytes")
      Logger.error("Stacktrace: #{inspect(__STACKTRACE__)}")
      {[], nil}
  end

  # Private helper to save preview frame (already annotated)
  # Saves frames to a fixed filename for live viewing
  # Only saves the live preview to minimize I/O overhead
  defp save_preview_frame(annotated_mat, preview_dir, _frame_count, _detection_count) do
    # Use a fixed filename so viewers can refresh to see latest frame
    preview_path = "#{preview_dir}/live_preview.jpg"
    Evision.imwrite(preview_path, annotated_mat)
  end

  # Draw bounding boxes and labels on image
  defp draw_detections(image, predictions, classes_list) do
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
