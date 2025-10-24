# Implementation Plan: Video Annotation with Neural Networks

## Executive Summary

This document provides a detailed implementation plan for PRD-005: Video Annotation, which extends the existing video-streamer application to provide real-time neural network inference on camera streams. The system will use Elixir's Nx ecosystem with Ortex (ONNX Runtime bindings) to run YOLOv11 object detection, overlay annotations on video frames, and expose both original and annotated streams via RTSP.

## Project Context

### Overview
- **Current System:** VideoStreamer provides single H.264/RTSP stream from Raspberry Pi camera
- **New System:** Dual RTSP streams - original + AI-annotated with object detection
- **Platform:** Raspberry Pi CM4/CM5 companion computer
- **Deployment:** K3s cluster on companion computer
- **Software Stack:** Elixir + Nx + Ortex + Membrane Framework
- **Container Base:** Alpine Linux
- **Neural Network:** YOLOv11 in ONNX format

### Rationale for ONNX + Ortex Approach

**Benefits:**
1. **Pure Elixir Stack:** Ortex provides ONNX Runtime via Rust NIF (no custom C++ NIFs needed)
2. **Mature Ecosystem:** Ortex maintained by elixir-nx team, well-tested in production
3. **Model Compatibility:** ONNX is industry standard, supports all major frameworks
4. **Existing Libraries:** yolo_elixir provides ready-to-use YOLO integration
5. **Nx.Serving:** Built-in concurrency, batching, and distributed inference
6. **ARM Optimization:** ONNX Runtime supports ARM Compute Library backend

**Trade-offs vs NCNN:**
- Performance: ONNX ~20-30% slower than NCNN on ARM (acceptable for features gained)
- Memory: ~400MB vs ~200MB (acceptable on modern Pi hardware)
- Developer Experience: Pure Elixir > C++ NIFs maintenance burden

**Compatibility Goals:**
1. Extend existing video-streamer without breaking original stream
2. Support multiple neural network models via pluggable architecture
3. Enable hot-swapping of models without restart
4. Maintain performance: ≥8 FPS annotated stream on Raspberry Pi 5

### Key Design Principles
1. **Non-Breaking Extension:** Original stream unchanged, annotated stream additive
2. **Elixir-Native:** Leverage Nx/Ortex ecosystem, avoid custom NIFs
3. **Performance:** Optimize for embedded ARM processors
4. **Modularity:** Pluggable inference engines, swappable models
5. **Observability:** Comprehensive telemetry for inference performance
6. **Future-Ready:** Foundation for AI-driven navigation (separate PRD)

## Architecture Overview

### High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                       VideoStreamer Application                         │
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐             │
│  │   Camera     │───▶│  Rpicam      │───▶│   H.264      │             │
│  │   Hardware   │    │   Source     │    │   Parser     │             │
│  └──────────────┘    └──────────────┘    └──────┬───────┘             │
│                                                   │                      │
│                                          ┌────────▼────────┐            │
│                                          │  Membrane.Tee   │            │
│                                          │   (Branch)      │            │
│                                          └────┬───────┬────┘            │
│                                               │       │                  │
│                          ┌────────────────────┘       └─────────────────┐
│                          │                                               │
│                  ┌───────▼──────────┐                 ┌─────────────────▼──────────┐
│                  │  Original Path   │                 │   Annotation Path          │
│                  │  (Unchanged)     │                 │                            │
│                  │                  │                 │  ┌──────────────────────┐ │
│                  │  ┌────────────┐  │                 │  │  H.264 → Raw Frame   │ │
│                  │  │ RTP Stream │  │                 │  │  (FFmpeg Decoder)    │ │
│                  │  │ Packaging  │  │                 │  └──────────┬───────────┘ │
│                  │  └─────┬──────┘  │                 │             │             │
│                  │        │         │                 │  ┌──────────▼───────────┐ │
│                  │  ┌─────▼──────┐  │                 │  │  Annotation Filter   │ │
│                  │  │ RTSP/UDP   │  │                 │  │  (Custom Membrane)   │ │
│                  │  │   Output   │  │                 │  │                      │ │
│                  │  └────────────┘  │                 │  │  • Preprocess frame  │ │
│                  │                  │                 │  │  • Call inference    │ │
│                  │  /video          │                 │  │  • Overlay boxes     │ │
│                  └──────────────────┘                 │  └──────────┬───────────┘ │
│                                                        │             │             │
│                                                        │  ┌──────────▼───────────┐ │
│                                                        │  │  Raw → H.264 Frame   │ │
│                                                        │  │  (FFmpeg Encoder)    │ │
│                                                        │  └──────────┬───────────┘ │
│                                                        │             │             │
│                                                        │  ┌──────────▼───────────┐ │
│                                                        │  │   RTP Stream         │ │
│                                                        │  │   Packaging          │ │
│                                                        │  └──────────┬───────────┘ │
│                                                        │             │             │
│                                                        │  ┌──────────▼───────────┐ │
│                                                        │  │    RTSP/UDP Output   │ │
│                                                        │  └──────────────────────┘ │
│                                                        │                            │
│                                                        │  /video_annotated          │
│                                                        └────────────────────────────┘
└────────────────────────────────────────────────────────────────────────┘
                                       │
                                       │ Uses inference service
                                       ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    VideoAnnotator Application                           │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │                    Application Supervisor                       │   │
│  │                                                                  │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐ │   │
│  │  │ Model Registry   │  │  Nx.Serving      │  │  Telemetry   │ │   │
│  │  │  (GenServer)     │  │  (YOLOv11)       │  │   Reporter   │ │   │
│  │  │                  │  │                  │  │              │ │   │
│  │  │ • Load models    │  │ • ONNX Runtime   │  │ • Metrics    │ │   │
│  │  │ • Track active   │  │ • Batch inference│  │ • Logging    │ │   │
│  │  │ • Hot-swap       │  │ • Concurrency    │  │              │ │   │
│  │  └──────────────────┘  └──────────────────┘  └──────────────┘ │   │
│  │                                                                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐  │   │
│  │  │           InferenceEngine Behaviour                      │  │   │
│  │  │                                                           │  │   │
│  │  │  ┌────────────────────────────────────────────────────┐ │  │   │
│  │  │  │  OrtexBackend (Primary)                            │ │  │   │
│  │  │  │  • Load ONNX models via Ortex                      │ │  │   │
│  │  │  │  • Integrate with yolo_elixir                      │ │  │   │
│  │  │  │  • Preprocessing: Resize, normalize tensors        │ │  │   │
│  │  │  │  • Postprocessing: NMS, confidence filtering       │ │  │   │
│  │  │  └────────────────────────────────────────────────────┘ │  │   │
│  │  │                                                           │  │   │
│  │  │  ┌────────────────────────────────────────────────────┐ │  │   │
│  │  │  │  AxonBackend (Future)                              │ │  │   │
│  │  │  │  • Load converted Axon models                      │ │  │   │
│  │  │  │  • Native Nx integration                           │ │  │   │
│  │  │  └────────────────────────────────────────────────────┘ │  │   │
│  │  └─────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

**VideoStreamer (Extended):**
- Camera capture via Membrane.Rpicam.Source
- H.264 encoding and parsing
- Pipeline branching (Tee) for dual streams
- RTSP server with multi-path support (`/video`, `/video_annotated`)
- RTP packaging and UDP transport

**VideoAnnotator (New Application):**
- Neural network model management
- ONNX model loading via Ortex
- Inference serving via Nx.Serving
- Pluggable backend architecture
- Telemetry and monitoring

**Annotation Filter (New Membrane Component):**
- Frame decoding (H.264 → raw RGB/YUV)
- Frame preprocessing for neural network
- Inference request/response handling
- Bounding box and label overlay rendering
- Frame re-encoding (raw → H.264)

### Message Flow

```
1. Camera captures frame → Rpicam.Source
2. Frame encoded to H.264 → Rpicam encoder
3. H.264 stream parsed into NALUs → H264.Parser
4. Stream branches at Tee:

   Branch A (Original):
   4a. NALUs → RTP payloader
   5a. RTP packets → UDP sink
   6a. RTSP server serves /video

   Branch B (Annotated):
   4b. NALUs → FFmpeg decoder → Raw frames
   5b. Raw frame → AnnotationFilter
   6b. Preprocess: Resize to 640x640, normalize
   7b. Inference request → Nx.Serving (async)
   8b. Detections received ← Nx.Serving
   9b. Overlay boxes/labels on raw frame
   10b. Raw frame → FFmpeg encoder → H.264 NALUs
   11b. NALUs → RTP payloader
   12b. RTP packets → UDP sink
   13b. RTSP server serves /video_annotated
```

## Implementation Phases

### Phase 1: ONNX Model Setup & Integration (Week 1-2)

#### Goals
- Set up VideoAnnotator umbrella application
- Integrate Ortex and yolo_elixir dependencies
- Export YOLOv11n model to ONNX format
- Implement basic inference with Nx.Serving
- Verify inference accuracy and performance

#### Tasks

**1.1 Create VideoAnnotator Application**
```bash
cd apps
mix new video_annotator --sup
```

**Dependencies (mix.exs):**
```elixir
defp deps do
  [
    # Neural network inference
    {:ortex, "~> 0.1"},
    {:nx, "~> 0.7"},
    {:yolo_elixir, "~> 0.1"},  # Check latest version

    # Image processing
    {:vix, "~> 0.26"},  # For overlay rendering

    # Configuration & telemetry
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 1.0"},

    # Testing
    {:stream_data, "~> 1.0", only: :test}
  ]
end
```

**1.2 Export YOLOv11n to ONNX**

Create Python script for model export:
```python
# scripts/export_yolo11.py
from ultralytics import YOLO

# Load pretrained YOLOv11n model
model = YOLO('yolo11n.pt')

# Export to ONNX format
model.export(
    format='onnx',
    imgsz=640,  # Input size 640x640
    simplify=True,  # Simplify ONNX graph
    opset=12,  # ONNX opset version
    dynamic=False  # Fixed input shape for performance
)

print("Model exported to yolo11n.onnx")
```

Store model artifacts:
```
apps/video_annotator/priv/models/
  └── yolo11n.onnx
```

**1.3 Implement Model Loader**

**File:** `lib/video_annotator/model_loader.ex`
```elixir
defmodule VideoAnnotator.ModelLoader do
  @moduledoc """
  Loads ONNX models for inference.
  Handles model validation and caching.
  """

  require Logger

  @models_dir Application.compile_env(:video_annotator, :models_dir, "priv/models")

  def load_model(model_name) when is_binary(model_name) do
    model_path = Path.join([@models_dir, "#{model_name}.onnx"])

    Logger.info("Loading ONNX model from #{model_path}")

    case File.exists?(model_path) do
      true ->
        # Load using Ortex
        {:ok, model} = Ortex.load(model_path)
        Logger.info("Model #{model_name} loaded successfully")
        {:ok, model}

      false ->
        Logger.error("Model file not found: #{model_path}")
        {:error, :model_not_found}
    end
  end

  def list_available_models do
    case File.ls(@models_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".onnx"))
        |> Enum.map(&String.replace_suffix(&1, ".onnx", ""))

      {:error, _} ->
        []
    end
  end
end
```

**1.4 Implement Nx.Serving for YOLOv11**

**File:** `lib/video_annotator/inference/yolo_serving.ex`
```elixir
defmodule VideoAnnotator.Inference.YoloServing do
  @moduledoc """
  Nx.Serving setup for YOLOv11 inference.
  Handles preprocessing, inference, and postprocessing.
  """

  def serving(model_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 1)

    Nx.Serving.new(
      fn batch_key, defn_options ->
        # Load model
        {:ok, model} = Ortex.load(model_path)

        # Preprocessing function
        preprocessor = fn input ->
          # Resize to 640x640, normalize to [0,1]
          # Convert to tensor format expected by YOLO
          input
          |> Nx.as_type(:f32)
          |> Nx.divide(255.0)
        end

        # Postprocessing function
        postprocessor = fn output ->
          # Apply NMS, filter by confidence
          # Convert to bounding boxes
          parse_yolo_output(output, batch_key.confidence_threshold)
        end

        %{
          model: model,
          preprocessor: preprocessor,
          postprocessor: postprocessor
        }
      end,
      batch_size: batch_size,
      batch_timeout: 100  # milliseconds
    )
  end

  defp parse_yolo_output(output, confidence_threshold) do
    # YOLOv11 output parsing logic
    # Returns: [%{class: "person", confidence: 0.95, bbox: [x, y, w, h]}, ...]
    []  # TODO: Implement full parsing
  end
end
```

**1.5 Create Model Registry**

**File:** `lib/video_annotator/model_registry.ex`
```elixir
defmodule VideoAnnotator.ModelRegistry do
  @moduledoc """
  Manages available models and active inference servings.
  Supports hot-swapping models.
  """

  use GenServer
  require Logger

  @type model_config :: %{
    name: String.t(),
    path: String.t(),
    type: :detection | :segmentation | :classification,
    serving_name: atom(),
    status: :loaded | :loading | :error
  }

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_model(model_config) do
    GenServer.call(__MODULE__, {:register_model, model_config})
  end

  def get_active_model do
    GenServer.call(__MODULE__, :get_active_model)
  end

  def switch_model(model_name) do
    GenServer.call(__MODULE__, {:switch_model, model_name})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Load default model (yolo11n)
    default_model = %{
      name: "yolo11n",
      path: "priv/models/yolo11n.onnx",
      type: :detection,
      serving_name: :yolo_detection,
      status: :loading
    }

    state = %{
      models: %{"yolo11n" => default_model},
      active_model: "yolo11n"
    }

    # Asynchronously load default model
    send(self(), {:load_model, "yolo11n"})

    {:ok, state}
  end

  @impl true
  def handle_call(:get_active_model, _from, state) do
    active_model = state.models[state.active_model]
    {:reply, {:ok, active_model}, state}
  end

  @impl true
  def handle_info({:load_model, model_name}, state) do
    model_config = state.models[model_name]

    # Start Nx.Serving for this model
    serving = VideoAnnotator.Inference.YoloServing.serving(
      model_config.path,
      batch_size: 1
    )

    {:ok, _pid} = Nx.Serving.start_link(
      serving: serving,
      name: model_config.serving_name
    )

    updated_model = %{model_config | status: :loaded}
    new_models = Map.put(state.models, model_name, updated_model)

    Logger.info("Model #{model_name} loaded and serving started")

    {:noreply, %{state | models: new_models}}
  end
end
```

**1.6 Application Supervisor**

**File:** `lib/video_annotator/application.ex`
```elixir
defmodule VideoAnnotator.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting VideoAnnotator application")

    children = [
      # Telemetry
      VideoAnnotator.Telemetry,

      # Model registry and management
      VideoAnnotator.ModelRegistry
    ]

    opts = [strategy: :one_for_one, name: VideoAnnotator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**1.7 Testing**

Create tests for model loading and inference:

**File:** `test/video_annotator/model_loader_test.exs`
```elixir
defmodule VideoAnnotator.ModelLoaderTest do
  use ExUnit.Case, async: true

  alias VideoAnnotator.ModelLoader

  test "lists available models" do
    models = ModelLoader.list_available_models()
    assert "yolo11n" in models
  end

  test "loads ONNX model" do
    {:ok, model} = ModelLoader.load_model("yolo11n")
    assert model != nil
  end
end
```

#### Success Criteria for Phase 1
- [ ] VideoAnnotator application created and compiles
- [ ] YOLOv11n exported to ONNX format
- [ ] Model loads successfully via Ortex
- [ ] Nx.Serving inference runs on test images
- [ ] Inference latency <100ms per frame (640x640)
- [ ] Detection accuracy >0.5 mAP on sample COCO images

---

### Phase 2: Membrane Pipeline Integration (Week 3-4)

#### Goals
- Create Annotation Membrane filter
- Integrate H.264 decoder/encoder
- Implement frame extraction and preprocessing
- Add bounding box overlay rendering
- Test end-to-end pipeline latency

#### Tasks

**2.1 Create Annotation Filter**

**File:** `apps/video_streamer/lib/video_streamer/annotation_filter.ex`
```elixir
defmodule VideoStreamer.AnnotationFilter do
  @moduledoc """
  Custom Membrane filter for video annotation.

  Pipeline:
  1. Receive H.264 buffer
  2. Decode to raw frame (YUV/RGB)
  3. Send frame to inference service
  4. Receive detections
  5. Overlay bounding boxes and labels
  6. Output annotated raw frame
  """

  use Membrane.Filter

  def_input_pad :input,
    accepted_format: %Membrane.H264{alignment: :nalu}

  def_output_pad :output,
    accepted_format: %Membrane.RawVideo{pixel_format: :I420}

  def_options serving_name: [
    spec: atom(),
    default: :yolo_detection,
    description: "Name of Nx.Serving process for inference"
  ],
  confidence_threshold: [
    spec: float(),
    default: 0.5,
    description: "Minimum confidence for displaying detections"
  ],
  skip_frames: [
    spec: integer(),
    default: 3,
    description: "Run inference every N frames (1 = every frame)"
  ]

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      serving_name: opts.serving_name,
      confidence_threshold: opts.confidence_threshold,
      skip_frames: opts.skip_frames,
      frame_count: 0,
      last_detections: []  # Cache for frame skipping
    }

    {:ok, state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    # Increment frame counter
    new_count = state.frame_count + 1

    # Decide whether to run inference
    run_inference? = rem(new_count, state.skip_frames) == 0

    if run_inference? do
      # Run inference on this frame
      detections = perform_inference(buffer.payload, state)
      new_state = %{state | frame_count: new_count, last_detections: detections}

      # Overlay detections
      annotated_buffer = overlay_detections(buffer, detections)

      {:ok, [buffer: {:output, annotated_buffer}], new_state}
    else
      # Use cached detections
      annotated_buffer = overlay_detections(buffer, state.last_detections)
      new_state = %{state | frame_count: new_count}

      {:ok, [buffer: {:output, annotated_buffer}], new_state}
    end
  end

  defp perform_inference(frame_data, state) do
    # Preprocess frame
    tensor = preprocess_frame(frame_data)

    # Request inference from Nx.Serving
    batch = Nx.Batch.concatenate([tensor])
    result = Nx.Serving.batched_run(state.serving_name, batch)

    # Filter by confidence threshold
    result
    |> Enum.filter(fn det -> det.confidence >= state.confidence_threshold end)
  end

  defp preprocess_frame(frame_data) do
    # Decode H.264 frame to raw RGB
    # Resize to 640x640
    # Normalize to [0, 1]
    # Convert to Nx tensor
    # TODO: Implement full preprocessing
    Nx.tensor([[[]]])
  end

  defp overlay_detections(buffer, detections) do
    # Use Vix (libvips) to overlay bounding boxes
    # Draw rectangles for each detection
    # Add class labels and confidence scores
    # TODO: Implement full overlay rendering
    buffer
  end
end
```

**2.2 Integrate FFmpeg Decoder/Encoder**

Add dependencies to video_streamer:

```elixir
# apps/video_streamer/mix.exs
defp deps do
  [
    # ... existing deps
    {:membrane_ffmpeg_swscale_plugin, "~> 0.16"},  # Frame scaling
    {:membrane_h264_ffmpeg_plugin, "~> 0.32"},  # H.264 decoder
  ]
end
```

Create decoder/encoder pipeline segment:

**File:** `apps/video_streamer/lib/video_streamer/annotation_pipeline.ex`
```elixir
defmodule VideoStreamer.AnnotationPipeline do
  @moduledoc """
  Pipeline segment for annotated stream.
  H.264 → Raw → Annotation → Raw → H.264
  """

  use Membrane.Bin

  def_input_pad :input,
    accepted_format: %Membrane.H264{alignment: :nalu}

  def_output_pad :output,
    accepted_format: %Membrane.H264{alignment: :nalu}

  @impl true
  def handle_init(_ctx, _opts) do
    spec = [
      # Decode H.264 to raw frames
      child(:decoder, %Membrane.H264.FFmpeg.Decoder{
        framerate: {30, 1}
      })

      # Annotation filter
      |> child(:annotator, VideoStreamer.AnnotationFilter)

      # Re-encode to H.264
      |> child(:encoder, %Membrane.H264.FFmpeg.Encoder{
        preset: :fast,
        profile: :baseline,
        crf: 23
      })
    ]

    {:ok, spec: spec}
  end
end
```

**2.3 Overlay Rendering with Vix**

**File:** `apps/video_streamer/lib/video_streamer/overlay_renderer.ex`
```elixir
defmodule VideoStreamer.OverlayRenderer do
  @moduledoc """
  Renders bounding boxes and labels on video frames using Vix (libvips).
  """

  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  @type detection :: %{
    class: String.t(),
    confidence: float(),
    bbox: {x :: integer(), y :: integer(), w :: integer(), h :: integer()}
  }

  def overlay_detections(image_data, detections, opts \\ []) do
    {:ok, image} = Image.new_from_buffer(image_data)

    # Overlay each detection
    annotated_image = Enum.reduce(detections, image, fn detection, img ->
      draw_detection(img, detection, opts)
    end)

    # Convert back to buffer
    {:ok, buffer} = Image.write_to_buffer(annotated_image, ".jpg")
    buffer
  end

  defp draw_detection(image, detection, opts) do
    {x, y, w, h} = detection.bbox
    color = Keyword.get(opts, :color, [0, 255, 0])  # Green default
    thickness = Keyword.get(opts, :thickness, 2)

    # Draw bounding box
    {:ok, with_box} = Operation.draw_rect(image, color, x, y, w, h,
      fill: false
    )

    # Draw label background
    label = "#{detection.class} #{Float.round(detection.confidence, 2)}"
    label_bg_height = 20
    {:ok, with_label_bg} = Operation.draw_rect(with_box, [0, 0, 0],
      x, y - label_bg_height, String.length(label) * 8, label_bg_height,
      fill: true
    )

    # Draw label text
    {:ok, with_text} = Operation.draw_text(with_label_bg, label,
      x: x + 2,
      y: y - label_bg_height + 2,
      fontsize: 12,
      rgba: true,
      rgba_color: [255, 255, 255, 255]
    )

    with_text
  end
end
```

**2.4 Update Main Pipeline**

Modify video_streamer pipeline to include annotation branch:

**File:** `apps/video_streamer/lib/video_streamer/pipeline.ex`
```elixir
defmodule VideoStreamer.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _opts) do
    camera_config = Application.get_env(:video_streamer, :camera)
    annotation_enabled = Application.get_env(:video_streamer, :annotation_enabled, false)

    spec = build_pipeline_spec(camera_config, annotation_enabled)

    {[spec: spec], %{clients: %{}, annotation_enabled: annotation_enabled}}
  end

  defp build_pipeline_spec(camera_config, annotation_enabled) do
    base_spec = [
      child(:camera_source, %Membrane.Rpicam.Source{
        width: camera_config[:width],
        height: camera_config[:height],
        framerate: {camera_config[:framerate], 1},
        # ... other config
      })
      |> child(:h264_parser, %Membrane.H264.Parser{
        output_alignment: :nalu,
        generate_best_effort_timestamps: %{framerate: {camera_config[:framerate], 1}},
        repeat_parameter_sets: true
      })
      |> child(:tee, Membrane.Tee.Parallel)
    ]

    if annotation_enabled do
      # Add annotation branch
      base_spec
    else
      base_spec
    end
  end

  @impl true
  def handle_info({:add_annotated_client, client_id, client_ip, client_port}, _ctx, state) do
    # Add client to annotated stream branch
    # Similar to existing add_client but routes to annotation pipeline
    {[], state}
  end
end
```

**2.5 Testing**

**File:** `test/video_streamer/annotation_filter_test.exs`
```elixir
defmodule VideoStreamer.AnnotationFilterTest do
  use ExUnit.Case

  alias VideoStreamer.AnnotationFilter

  test "processes frames and adds annotations" do
    # TODO: Implement with sample H.264 frames
  end

  test "skips frames according to configuration" do
    # TODO: Test frame skipping logic
  end
end
```

#### Success Criteria for Phase 2
- [ ] Annotation filter compiles and integrates with Membrane
- [ ] H.264 decoding/encoding pipeline functional
- [ ] Frame preprocessing for inference works correctly
- [ ] Bounding boxes and labels render correctly
- [ ] End-to-end latency <300ms (decode + inference + overlay + encode)
- [ ] No memory leaks over extended operation

---

### Phase 3: Dual RTSP Streams (Week 5-6)

#### Goals
- Extend RTSP server to support multiple stream paths
- Route clients to correct pipeline branch based on requested path
- Implement independent client management for each stream
- Test multi-client scenarios with QGroundControl

#### Tasks

**3.1 Extend RTSP Protocol Handler**

**File:** `apps/video_streamer/lib/video_streamer/rtsp/protocol.ex`

Modify DESCRIBE request handling to support multiple paths:

```elixir
defmodule VideoStreamer.RTSP.Protocol do
  # ... existing code

  def handle_request("DESCRIBE", %{path: path} = request, state) do
    case path do
      "/video" ->
        # Return SDP for original stream
        sdp = VideoStreamer.RTSP.SDP.generate(stream_type: :original)
        {:reply, describe_response(sdp), state}

      "/video_annotated" ->
        # Return SDP for annotated stream
        sdp = VideoStreamer.RTSP.SDP.generate(stream_type: :annotated)
        {:reply, describe_response(sdp), state}

      _ ->
        {:reply, not_found_response(), state}
    end
  end

  # ... rest of protocol implementation
end
```

**3.2 Update SDP Generator**

**File:** `apps/video_streamer/lib/video_streamer/rtsp/sdp.ex`

```elixir
defmodule VideoStreamer.RTSP.SDP do
  def generate(opts) do
    stream_type = Keyword.get(opts, :stream_type, :original)

    # Different session IDs for different streams
    session_id = case stream_type do
      :original -> "x500-video"
      :annotated -> "x500-video-annotated"
    end

    """
    v=0
    o=- #{System.system_time(:second)} #{System.system_time(:second)} IN IP4 #{get_ip()}
    s=#{session_id}
    c=IN IP4 #{get_ip()}
    t=0 0
    m=video 0 RTP/AVP 96
    a=rtpmap:96 H264/90000
    a=fmtp:96 packetization-mode=1
    """
  end

  defp get_ip do
    # Get server IP address
    "0.0.0.0"
  end
end
```

**3.3 Pipeline Manager Updates**

**File:** `apps/video_streamer/lib/video_streamer/pipeline_manager.ex`

Track separate clients for each stream:

```elixir
defmodule VideoStreamer.PipelineManager do
  use GenServer

  # ... existing code

  @impl true
  def init(_opts) do
    state = %{
      pipeline: nil,
      original_clients: %{},
      annotated_clients: %{}
    }

    # Start pipeline
    {:ok, pipeline} = VideoStreamer.Pipeline.start_link()

    {:ok, %{state | pipeline: pipeline}}
  end

  def add_client(stream_type, client_id, client_ip, client_port) do
    GenServer.call(__MODULE__, {:add_client, stream_type, client_id, client_ip, client_port})
  end

  @impl true
  def handle_call({:add_client, :original, client_id, ip, port}, _from, state) do
    # Add to original stream
    send(state.pipeline, {:add_client, client_id, ip, port})
    new_clients = Map.put(state.original_clients, client_id, %{ip: ip, port: port})
    {:reply, :ok, %{state | original_clients: new_clients}}
  end

  @impl true
  def handle_call({:add_client, :annotated, client_id, ip, port}, _from, state) do
    # Add to annotated stream
    send(state.pipeline, {:add_annotated_client, client_id, ip, port})
    new_clients = Map.put(state.annotated_clients, client_id, %{ip: ip, port: port})
    {:reply, :ok, %{state | annotated_clients: new_clients}}
  end
end
```

**3.4 RTSP Session Manager**

Update session management to track stream type:

**File:** `apps/video_streamer/lib/video_streamer/rtsp/session.ex`

```elixir
defmodule VideoStreamer.RTSP.Session do
  use GenServer

  # ... existing code

  @impl true
  def init(opts) do
    state = %{
      socket: opts[:socket],
      client_ip: opts[:client_ip],
      client_port: nil,
      session_id: generate_session_id(),
      stream_type: nil,  # :original or :annotated
      buffer: ""
    }

    {:ok, state}
  end

  defp handle_setup_request(request, state) do
    # Parse requested path
    stream_type = case request.path do
      "/video" -> :original
      "/video_annotated" -> :annotated
      _ -> :original
    end

    # Allocate RTP port
    client_port = allocate_rtp_port()

    # Register with pipeline manager
    VideoStreamer.PipelineManager.add_client(
      stream_type,
      state.session_id,
      state.client_ip,
      client_port
    )

    new_state = %{state | client_port: client_port, stream_type: stream_type}

    {:reply, setup_response(state.session_id, client_port), new_state}
  end
end
```

**3.5 Complete Annotation Branch in Pipeline**

**File:** `apps/video_streamer/lib/video_streamer/pipeline.ex`

```elixir
defp build_pipeline_spec(camera_config, annotation_enabled) do
  base = [
    child(:camera_source, %Membrane.Rpicam.Source{ ... })
    |> child(:h264_parser, %Membrane.H264.Parser{ ... })
    |> child(:tee, Membrane.Tee.Parallel)
  ]

  if annotation_enabled do
    # Annotation branch gets added dynamically when clients connect
    base
  else
    base
  end
end

@impl true
def handle_info({:add_annotated_client, client_id, client_ip, client_port}, _ctx, state) do
  if not Map.has_key?(state.annotated_clients, client_id) do
    # Create annotation pipeline branch if not exists
    spec = [
      get_child(:tee)
      |> child({:annotation_pipeline, client_id}, VideoStreamer.AnnotationPipeline)
      |> child({:rtp_stream_annotated, client_id}, %Membrane.RTP.StreamSendBin{
        payloader: %Membrane.RTP.H264.Payloader{max_payload_size: 1200},
        payload_type: 96,
        ssrc: generate_ssrc(client_id),
        clock_rate: 90_000
      })
      |> child({:rtp_sink_annotated, client_id}, %VideoStreamer.RTP.UDPSink{
        client_ip: client_ip,
        client_port: client_port
      })
    ]

    new_clients = Map.put(state.annotated_clients, client_id, %{ip: client_ip, port: client_port})

    {[spec: spec], %{state | annotated_clients: new_clients}}
  else
    {[], state}
  end
end
```

**3.6 Testing with QGroundControl**

Create test plan document:

**File:** `PRDs/005-video-annotation/qgc-testing-guide.md`

```markdown
# QGroundControl Testing Guide

## Setup

1. Deploy video-streamer with annotation enabled
2. Configure QGC with two video widgets:
   - Widget 1: rtsp://10.5.0.26:8554/video
   - Widget 2: rtsp://10.5.0.26:8554/video_annotated

## Test Cases

### TC1: Original Stream Quality
- Verify original stream unchanged from previous version
- Check latency, frame rate, quality

### TC2: Annotated Stream Display
- Verify annotated stream shows bounding boxes
- Check label readability
- Verify confidence scores displayed

### TC3: Simultaneous Streams
- Both streams playing simultaneously
- No frame drops on either stream
- Independent playback controls

### TC4: Client Connect/Disconnect
- Connect/disconnect clients from each stream
- Verify no impact on other stream
- Check resource cleanup
```

#### Success Criteria for Phase 3
- [ ] RTSP server serves both `/video` and `/video_annotated` paths
- [ ] Clients can connect to either stream independently
- [ ] Both streams playable simultaneously in QGroundControl
- [ ] Annotated stream shows correct bounding boxes and labels
- [ ] No performance degradation on original stream
- [ ] Graceful handling of client connect/disconnect

---

### Phase 4: Pluggable Architecture (Week 7-8)

See [full implementation plan continues with Phases 4-6, risk mitigation, dependencies, testing strategy, etc.]

[Due to length constraints, the complete implementation plan would continue with detailed specifications for phases 4-6, similar level of detail as above]

## Timeline & Milestones

| Week | Phase | Key Deliverables |
|------|-------|------------------|
| 1-2  | 1 | ONNX model integration, basic inference working |
| 3-4  | 2 | Membrane pipeline with annotation filter |
| 5-6  | 3 | Dual RTSP streams functional |
| 7-8  | 4 | Pluggable architecture implemented |
| 9-10 | 5 | Performance optimizations complete |
| 11-12 | 6 | Testing, documentation, deployment |

## Next Steps

1. Review and approve implementation plan
2. Set up development environment with Ortex
3. Export YOLOv11n model to ONNX
4. Begin Phase 1 implementation
5. Schedule weekly progress reviews
