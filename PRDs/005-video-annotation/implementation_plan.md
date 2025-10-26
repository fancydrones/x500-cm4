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
- **Neural Network:** YOLOX-Nano in ONNX format (proven in Phase 0, YOLOv11 future option)

### Phase 0: Development Pipeline (Completed)

**Status**: ✅ COMPLETE (October 26, 2025)

Phase 0 established the core annotation pipeline on macOS for development and testing.

#### Key Components Developed:
- ✅ `YoloDetector` - Filter with time-based adaptive frame skipping
- ✅ `WebPreview` - Bandit MJPEG server for development monitoring
- ✅ `Pipeline` - Camera → Toilet → YoloDetector → Sink
- ✅ `test_web_preview.exs` - Development start script

#### Proven Architecture Patterns:
1. **Auto flow control** with `toilet_capacity: 1`
2. **Time-based frame skipping** (270ms target on macOS)
3. **Two-level frame dropping** (toilet + time-based)
4. **Frame-ID tracking** for low-latency preview
5. **Evision** for image processing (better than Vix for video)

#### Performance Achieved:
- macOS: 6-7 FPS adaptive processing
- Inference: 130-180ms per frame
- Preview latency: <100ms
- Memory: Stable, no leaks

**Reference Implementation**: [apps/video_annotator/](../../apps/video_annotator/)

**Documentation**:
- [PIPELINE_ARCHITECTURE.md](../../apps/video_annotator/PIPELINE_ARCHITECTURE.md)
- [README_PIPELINE.md](../../apps/video_annotator/README_PIPELINE.md)
- [PHASE_0_COMPLETE.md](../../apps/video_annotator/PHASE_0_COMPLETE.md)
- [phase_0_learnings_update.md](phase_0_learnings_update.md)

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
4. Maintain performance: 2-4 FPS annotated stream on Raspberry Pi 4/5 (adaptive, based on Phase 0 learnings)

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

### Phase 1: Raspberry Pi Deployment with ARM Acceleration (Week 1-3)

#### Goals
- Adapt Phase 0 code for Raspberry Pi deployment
- Build ONNX Runtime with ARM Compute Library (ACL) for hardware acceleration
- Deploy to Raspberry Pi and benchmark performance
- Achieve 6-10 FPS minimum viable performance (2-3x speedup over CPU)

#### Rationale: Hardware Acceleration is Critical

Phase 0 proved hardware acceleration provides massive speedup:
- **macOS CPU (EXLA)**: 3.7 FPS baseline
- **macOS GPU (EMLX/Metal)**: 11.5 FPS → **3.1x speedup** 🚀

This validates investing in ARM acceleration for Raspberry Pi:
- **RPi CPU (EXLA)**: 2-4 FPS estimated
- **RPi ACL (ARM NEON)**: 6-10 FPS target → **2-3x speedup** 🎯

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
    # Neural network inference (proven in Phase 0)
    {:yolo, ">= 0.2.0"},  # Use yolo (supports YOLOX), not yolo_elixir
    {:ortex, "~> 0.1"},
    {:nx, "~> 0.7"},
    {:exla, "~> 0.9"},  # CPU backend

    # Image processing (Evision better than Vix for video)
    {:evision, "~> 0.2"},

    # Web preview (development only)
    {:plug, "~> 1.15", only: :dev},
    {:bandit, "~> 1.0", only: :dev},

    # Configuration & telemetry
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 1.0"},

    # Testing
    {:stream_data, "~> 1.0", only: :test}
  ]
end
```

**1.2 Download/Export YOLOX-Nano Model**

**Recommended (Proven in Phase 0)**: Use YOLOX-Nano
- Download from: https://github.com/Megvii-BaseDetection/YOLOX
- Model size: 3.5MB
- Already in ONNX format
- Works with `{:yolo, ">= 0.2.0"}` library

**Alternative (Future)**: Export YOLOv11n to ONNX
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
  ├── yolox_nano.onnx  # Recommended (Phase 0 proven)
  ├── coco_classes.json
  └── yolo11n.onnx  # Alternative (future)
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

**1.8 Build Docker Image with ARM Compute Library (ACL)**

**Critical for Raspberry Pi performance!**

Phase 0 proved hardware acceleration is essential:
- macOS: EMLX provided 3.1x speedup (3.7 → 11.5 FPS)
- RPi needs similar: ACL expected to provide 2-3x speedup

**File:** `apps/video_streamer/Dockerfile.acl`

Multi-stage build (see [PRDs/005-video-annotation/Dockerfile.acl](Dockerfile.acl)):
1. Build ARM Compute Library from source
2. Build ONNX Runtime with ACL support (~45 min first time)
3. Build Elixir app with custom ONNX Runtime
4. Create lightweight runtime image

**Build command:**
```bash
# Copy Dockerfile to video_streamer
cp PRDs/005-video-annotation/Dockerfile.acl apps/video_streamer/

# Build for ARM64 with ACL
docker buildx build \
  --platform linux/arm64 \
  --file apps/video_streamer/Dockerfile.acl \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-$(git rev-parse --short HEAD) \
  --tag ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest \
  --cache-from type=registry,ref=ghcr.io/fancydrones/x500-cm4/video-streamer:acl-buildcache \
  --cache-to type=registry,ref=ghcr.io/fancydrones/x500-cm4/video-streamer:acl-buildcache,mode=max \
  --push \
  apps/video_streamer
```

**1.9 Configure Application for ACL**

Update YOLO model loading to use ACL execution provider:

```elixir
# apps/video_annotator/lib/video_annotator/yolo_detector.ex (line ~90)

model = YOLO.load(
  model_path: state.model_path,
  classes_path: state.classes_path,
  model_impl: YOLO.Models.YOLOX,
  eps: [:acl, :cpu]  # Try ACL first, fallback to CPU
)
```

**1.10 Deploy and Benchmark on Raspberry Pi**

Deploy ACL-enabled image:
```bash
kubectl set image deployment/video-streamer \
  video-streamer=ghcr.io/fancydrones/x500-cm4/video-streamer:acl-latest
```

Monitor performance:
```bash
kubectl logs -f deployment/video-streamer | grep -E "(Frame [0-9]+:|FPS)"
```

Expected output:
```
[info] Using execution providers: [:acl, :cpu]
[info] Loaded model with [:acl] execution providers
[info] Frame 30: ... avg 200ms (5.0 FPS)   # 2.5x over CPU baseline!
[info] Frame 60: ... avg 166ms (6.0 FPS)
[info] Frame 90: ... avg 142ms (7.0 FPS)
```

**Reference Documentation:**
- [ACL Research Findings](ACL_RESEARCH_FINDINGS.md)
- [ACL Implementation Plan](ACL_IMPLEMENTATION_PLAN.md)
- [RPi Hardware Acceleration Options](rpi_hardware_acceleration_research.md)

#### Success Criteria for Phase 1
- [ ] VideoAnnotator application created and compiles
- [ ] YOLOX-Nano model downloaded and integrated
- [ ] Model loads successfully via YOLO library
- [ ] YOLO.detect() runs on test images
- [ ] Inference latency 130-180ms per frame on macOS (300-500ms expected on RPi without ACL)
- [ ] Detection accuracy validated with Phase 0 reference
- [ ] Web preview server working with live FPS display (development tool)
- [ ] **Docker image with ACL builds successfully** ⭐
- [ ] **ACL execution provider loads on Raspberry Pi** ⭐
- [ ] **Achieves 6-10 FPS on RPi 4 (2-3x speedup over CPU)** ⭐
- [ ] **Falls back to CPU gracefully if ACL unavailable** ⭐

---

### Phase 1.5: Dual-Path Pipeline for Smooth Piloting (Week 4)

#### Goals
- Provide smooth 30 FPS original stream for drone piloting
- Overlay 2-4 FPS annotations on separate RTSP stream
- QGroundControl compatibility with dual video widgets
- Server-side rendering (no client-side JavaScript required)

#### Rationale: Pilot Needs Smooth Video

**Current limitation**: 2-4 FPS annotated video too slow for navigation

**User requirement**:
- Pilot needs **smooth 30 FPS** for drone control
- Annotations useful but can be delayed (250-500ms acceptable)

**Solution**: Split camera stream into two paths
1. **Original path**: 30 FPS, no processing → `/video` (piloting)
2. **Detection path**: 2-4 FPS with annotations → `/video_annotated` (situational awareness)

#### Architecture

```
┌────────────────────────────────────────────────────────────┐
│                   Raspberry Pi Camera                       │
│                      (30 FPS NV12)                          │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       │ Membrane.Tee (split stream)
                       │
        ┌──────────────┴──────────────┐
        │                              │
        ▼                              ▼
┌───────────────────┐        ┌─────────────────────┐
│  Original Path    │        │   Detection Path    │
│    (30 FPS)       │        │     (2-4 FPS)       │
├───────────────────┤        ├─────────────────────┤
│ • H.264 encode    │        │ • Toilet (drop old) │
│ • No processing   │        │ • YOLO detection    │
│ • Direct to RTP   │        │ • Draw annotations  │
└────────┬──────────┘        └──────────┬──────────┘
         │                              │
         │                              │
         └─────────────────┬────────────┘
                           ▼
                  ┌─────────────────┐
                  │  RTSP Server    │
                  │  (Two streams)  │
                  ├─────────────────┤
                  │ • /video (30 FPS)
                  │ • /video_annotated (2-4 FPS)
                  └─────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │  QGroundControl │
                  │  (Two widgets)  │
                  ├─────────────────┤
                  │ Widget 1: Original (smooth piloting)
                  │ Widget 2: Annotated (object detection)
                  └─────────────────┘
```

#### Tasks

**1.5.1 Extend Pipeline with Membrane.Tee**

**File**: `apps/video_streamer/lib/video_streamer/pipeline.ex`

Add Tee to split camera stream:

```elixir
spec = [
  child(:camera, %Membrane.Rpicam.Source{...})
  |> child(:h264_parser, %Membrane.H264.Parser{...})
  |> child(:tee, Membrane.Tee.Parallel)
]

# Original path (30 FPS) - No processing
spec = spec ++ [
  get_child(:tee)
  |> via_out(Pad.ref(:output, 0))
  # Direct to RTP packaging, no processing
  |> child(:rtp_original, %Membrane.RTP.StreamSendBin{...})
  # ... RTSP sink for /video
]

# Detection path (2-4 FPS) - Process and annotate
spec = spec ++ [
  get_child(:tee)
  |> via_out(Pad.ref(:output, 1))
  |> child(:decoder, %Membrane.H264.FFmpeg.Decoder{...})
  |> via_in(:input, toilet_capacity: 1)  # Drop old frames
  |> child(:annotator, %VideoStreamer.AnnotationFilter{
      model_path: opts[:model_path],
      classes_path: opts[:classes_path],
      eps: [:acl, :cpu]  # Use ACL acceleration
    })
  |> child(:encoder, %Membrane.H264.FFmpeg.Encoder{...})
  |> child(:rtp_annotated, %Membrane.RTP.StreamSendBin{...})
  # ... RTSP sink for /video_annotated
]
```

**1.5.2 Adapt AnnotationFilter for Server-Side Rendering**

Based on Phase 0 YoloDetector, create server-side annotation filter:
- Auto flow control (proven in Phase 0)
- Time-based adaptive frame skipping
- Server-side drawing with Evision
- Output annotated raw frames (for re-encoding)

See [Phase 0 YoloDetector](../../apps/video_annotator/lib/video_annotator/yolo_detector.ex) for reference implementation.

**1.5.3 QGroundControl Configuration**

No code changes needed - QGC already supports dual video widgets!

**Configuration**:
- Widget 1: `rtsp://10.5.0.26:8554/video` (30 FPS original)
- Widget 2: `rtsp://10.5.0.26:8554/video_annotated` (2-4 FPS with boxes)

**Testing**:
- Deploy to drone
- Configure QGC dual widgets
- Verify smooth piloting with original stream
- Verify annotations visible on secondary stream

**Reference Documentation**:
- [DUAL_PATH_DECISION.md](DUAL_PATH_DECISION.md) - Complete implementation plan
- [DUAL_PATH_PIPELINE_ANALYSIS.md](DUAL_PATH_PIPELINE_ANALYSIS.md) - Architecture analysis

#### Performance Impact

**CPU usage** (with ACL):
- Original path: ~5-10% (H.264 encode only)
- Detection path: ~35-40% (decode + ACL + annotate + encode)
- **Total: ~45-50% CPU** (acceptable on RPi 4/5)

**Network bandwidth**:
- Original stream: ~6 Mbps (1552x1552 @ 30 FPS)
- Annotated stream: ~2 Mbps (1552x1552 @ 2-4 FPS or 640x640 compressed)
- **Total: ~8 Mbps** (acceptable on WiFi)

**User experience**:
- **Pilot**: Smooth 30 FPS navigation ✅
- **Situational awareness**: Detection boxes visible with slight delay (250-500ms)
- **QGC compatibility**: Standard RTSP, no modifications needed ✅

#### Future Enhancement

**Autonomous Navigation Output** (Future PRD):

Detection metadata can be output separately for autopilot:
```
Detection Path
   ├─→ Annotated video → Pilot (visual)
   └─→ Detection metadata → Autopilot (navigation)
       ├─→ Object positions (x, y, z)
       ├─→ Collision risk assessment
       └─→ MAVLink commands
```

**Not in current scope** - focus on pilot-visible annotations first.

#### Success Criteria for Phase 1.5
- [ ] Original stream maintains **30 FPS** smooth video
- [ ] Annotated stream shows **2-4 FPS** with visible detection boxes
- [ ] Both RTSP streams accessible simultaneously
- [ ] QGC dual widget configuration working
- [ ] CPU usage < 50%
- [ ] Network bandwidth < 10 Mbps
- [ ] No frame drops on original stream
- [ ] Annotations appear within 500ms of detection

---

### Phase 2: Membrane Pipeline Integration (Week 5-6)

#### Goals
- Create Annotation Membrane filter
- Integrate H.264 decoder/encoder
- Implement frame extraction and preprocessing
- Add bounding box overlay rendering
- Test end-to-end pipeline latency

#### Tasks

**2.1 Create Annotation Filter**

**File:** `apps/video_streamer/lib/video_streamer/annotation_filter.ex`

**IMPORTANT**: This implementation is based on proven Phase 0 architecture. Do NOT use manual flow control.

```elixir
defmodule VideoStreamer.AnnotationFilter do
  @moduledoc """
  Custom Membrane filter for video annotation with adaptive processing.

  Key Features (Proven in Phase 0):
  - Auto flow control (not manual)
  - Time-based adaptive frame skipping
  - Direct YOLO integration (no separate serving needed)
  - Low-latency processing
  """

  use Membrane.Filter

  def_input_pad :input,
    accepted_format: Membrane.RawVideo,
    flow_control: :auto  # IMPORTANT: Use auto, not manual

  def_output_pad :output,
    accepted_format: Membrane.RawVideo,
    flow_control: :auto

  def_options model_path: [
    spec: String.t(),
    description: "Path to ONNX model file"
  ],
  classes_path: [
    spec: String.t(),
    description: "Path to class labels JSON"
  ],
  target_interval_ms: [
    spec: pos_integer(),
    default: 500,  # 500ms for RPi (~2 FPS)
    description: "Minimum time between frame processing (adaptive threshold)"
  ]

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      model_path: opts.model_path,
      classes_path: opts.classes_path,
      target_interval_ms: opts.target_interval_ms,
      model: nil,
      classes: nil,
      frame_count: 0,
      last_process_time: 0,
      total_inference_time: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    # Load YOLO model
    Logger.info("Loading YOLO model from: #{state.model_path}")

    model = YOLO.load(
      model_path: state.model_path,
      classes_path: state.classes_path,
      model_impl: YOLO.Models.YOLOX
    )

    {:ok, classes_json} = File.read(state.classes_path)
    classes = Jason.decode!(classes_json)

    Logger.info("YOLO model loaded successfully")

    {[], %{state | model: model, classes: classes}}
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    current_time = System.monotonic_time(:millisecond)
    time_since_last = current_time - state.last_process_time

    # TIME-BASED ADAPTIVE SKIPPING - Critical for low latency!
    if time_since_last < state.target_interval_ms && state.frame_count > 0 do
      # Skip this frame - too soon since last processing
      {[buffer: {:output, buffer}], state}
    else
      # Process this frame
      start_time = current_time

      # Run YOLO detection (handles preprocessing internally)
      detections = YOLO.detect(state.model, buffer.payload)

      inference_time = System.monotonic_time(:millisecond) - start_time

      # Draw annotations
      annotated_buffer = draw_detections(buffer, detections, state.classes)

      # Update stats
      frame_count = state.frame_count + 1
      total_time = state.total_inference_time + inference_time

      if rem(frame_count, 30) == 0 do
        avg_time = total_time / frame_count
        fps = 1000.0 / avg_time
        Logger.info("Frame #{frame_count}: #{length(detections)} detections, " <>
                    "#{inference_time}ms, avg #{Float.round(avg_time, 1)}ms (#{Float.round(fps, 1)} FPS)")
      end

      new_state = %{
        state
        | frame_count: frame_count,
          total_inference_time: total_time,
          last_process_time: current_time
      }

      {[buffer: {:output, annotated_buffer}], new_state}
    end
  end

  defp draw_detections(buffer, detections, classes) do
    # Use Evision to draw bounding boxes
    # Convert buffer to Evision Mat
    # Draw rectangles and labels
    # Convert back to buffer
    # See Phase 0 reference: apps/video_annotator/lib/video_annotator/yolo_detector.ex
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

      # CRITICAL: toilet_capacity: 1 drops old frames before processor
      # This is essential for low-latency preview (proven in Phase 0)
      |> via_in(:input, toilet_capacity: 1)

      # Annotation filter with time-based skipping
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

**2.3 Overlay Rendering with Evision**

**File:** `apps/video_streamer/lib/video_streamer/overlay_renderer.ex`

**NOTE**: Use Evision (not Vix) - proven better for video in Phase 0

```elixir
defmodule VideoStreamer.OverlayRenderer do
  @moduledoc """
  Renders bounding boxes and labels on video frames using Evision (OpenCV).

  Based on proven Phase 0 implementation.
  """

  @type detection :: %{
    class: String.t(),
    confidence: float(),
    bbox: {x :: integer(), y :: integer(), w :: integer(), h :: integer()}
  }

  def overlay_detections(mat, detections, classes, opts \\ []) do
    # Iterate through detections and draw on mat
    Enum.reduce(detections, mat, fn detection, img ->
      draw_detection(img, detection, classes, opts)
    end)
  end

  defp draw_detection(mat, detection, classes, opts) do
    %{class_id: class_id, confidence: conf, bbox: {x, y, w, h}} = detection

    color = Keyword.get(opts, :color, {0, 255, 0})  # Green default
    thickness = Keyword.get(opts, :thickness, 2)

    class_name = Map.get(classes, class_id, "unknown")

    # Draw bounding box
    mat = Evision.rectangle(mat, {x, y}, {x + w, y + h}, color,
      thickness: thickness
    )

    # Draw label with background
    label = "#{class_name} #{Float.round(conf, 2)}"
    font = Evision.Constant.cv_FONT_HERSHEY_SIMPLEX()
    font_scale = 0.5

    # Get text size for background rectangle
    {{text_w, text_h}, _baseline} = Evision.getTextSize(label, font, font_scale, 1)

    # Draw label background (black rectangle)
    mat = Evision.rectangle(mat, {x, y - text_h - 4}, {x + text_w, y}, {0, 0, 0},
      thickness: -1  # Filled rectangle
    )

    # Draw label text (white)
    mat = Evision.putText(mat, label, {x, y - 2}, font, font_scale, {255, 255, 255},
      thickness: 1
    )

    mat
  end
end
```

**Reference**: See [apps/video_annotator/lib/video_annotator/yolo_detector.ex](../../apps/video_annotator/lib/video_annotator/yolo_detector.ex) lines 230-280 for working implementation.

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
- [ ] Bounding boxes and labels render correctly using Evision
- [ ] End-to-end latency <600ms on RPi (adaptive, based on Phase 0 learnings)
- [ ] No "Toilet overflow" errors in logs (verify auto flow control working)
- [ ] Preview shows current frames with <200ms lag when moving camera
- [ ] No memory leaks over extended operation
- [ ] Time-based adaptive skipping working (verified by log output)

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

## Expected Performance

Based on Phase 0 learnings:

| Stream | Frame Rate | Latency | Notes |
|--------|-----------|---------|-------|
| Original | 25-30 FPS | <100ms | Unchanged |
| Annotated | 2-4 FPS (adaptive) | <600ms | Varies with CPU load |

**Important**: Annotated stream FPS will vary based on:
- CPU load and scene complexity
- Number of detected objects
- This is expected behavior due to adaptive processing

## Test Cases

### TC1: Original Stream Quality
- Verify original stream unchanged from previous version
- Check latency, frame rate, quality
- Expected: 25-30 FPS, <100ms latency

### TC2: Annotated Stream Display
- Verify annotated stream shows bounding boxes
- Check label readability
- Verify confidence scores displayed
- Expected: 2-4 FPS adaptive, bounding boxes accurate

### TC3: Adaptive Performance
- Monitor FPS during varying CPU load
- Verify preview shows current frames (move camera, check lag <200ms)
- Check logs for "Toilet overflow" errors (should be none)
- Verify time-based skipping in logs

### TC4: Simultaneous Streams
- Both streams playing simultaneously
- No frame drops on original stream
- Independent playback controls
- Verify no performance degradation on original stream

### TC5: Client Connect/Disconnect
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

| Week | Phase | Key Deliverables | Notes |
|------|-------|------------------|-------|
| 0 (Done) | 0 | macOS development pipeline, web preview | ✅ COMPLETE |
| 1-2  | 1 | RPi model setup, adapt Phase 0 code | Use Phase 0 as starting point |
| 3-4  | 2 | Integrate with video-streamer pipeline | Apply Phase 0 patterns |
| 5-6  | 3 | Dual RTSP streams functional | - |
| 7-8  | 4 | Pluggable architecture implemented | - |
| 9-10 | 5 | Performance optimizations complete | - |
| 11-12 | 6 | Testing, documentation, deployment | - |

**Time Saved**: ~2 weeks due to Phase 0 proving the core architecture

## Next Steps

1. ✅ **Phase 0 Complete** - macOS development pipeline validated
2. Review updated implementation plan with Phase 0 learnings
3. Begin Phase 1 implementation using Phase 0 code as foundation:
   - Copy proven components from `apps/video_annotator/`
   - Adjust `target_interval_ms` from 270ms to 500-600ms for RPi
   - Test with Raspberry Pi camera format (likely I420, not NV12)
4. Apply Phase 0 architecture patterns:
   - Auto flow control with `toilet_capacity: 1`
   - Time-based adaptive frame skipping
   - Evision for image processing
   - Web preview for development (optional but recommended)
5. Schedule weekly progress reviews
