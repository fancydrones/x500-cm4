# Phase 0 Quick-Start Guide: Local macOS Development

**Goal:** Get video annotation working on your macOS development machine with webcam in <1 hour.

**Why Phase 0?** Rapid iteration is critical for ML development. This phase establishes a fast feedback loop (~30s from code change to result) before deploying to Raspberry Pi hardware.

---

## Prerequisites

### Software Requirements
- macOS Ventura 13+ (for best CoreML support)
- Homebrew installed
- Elixir 1.18+ (`brew install elixir`)
- Python 3.10+ (`brew install python@3.10`)
- FFmpeg (`brew install ffmpeg`)

### Hardware Requirements
- Built-in webcam or USB camera
- ~2GB free disk space
- Apple Silicon (M1/M2/M3) recommended for CoreML acceleration

### Time Estimate
- Model export: ~10 minutes
- App setup: ~15 minutes
- First working demo: ~30 minutes
- **Total: ~1 hour**

---

## Step 1: Export YOLOv11n Model (10 minutes)

### Install Python Dependencies

```bash
# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate

# Install Ultralytics (includes PyTorch and all dependencies)
pip install ultralytics
```

### Export Model to ONNX

```bash
# Option 1: Use CLI (simplest)
yolo export model=yolo11n.pt format=onnx imgsz=640 simplify=True

# Option 2: Use Python script (more control)
python3 <<'EOF'
from ultralytics import YOLO

# Load pretrained YOLOv11n (auto-downloads first time ~6MB)
model = YOLO('yolo11n.pt')

# Export to ONNX
model.export(
    format='onnx',
    imgsz=640,
    simplify=True,
    opset=12,
    dynamic=False  # Fixed input size for better performance
)

print("✓ Model exported to yolo11n.onnx")
EOF
```

**Output:** `yolo11n.onnx` file (~6MB)

### Download COCO Classes

```bash
# Download class labels
curl -L -o coco_classes.json https://raw.githubusercontent.com/amikelive/coco-labels/master/coco-labels-2014_2017.json
```

### Move to App Directory

```bash
# Create models directory and move files
mkdir -p apps/video_annotator/priv/models
mv yolo11n.onnx apps/video_annotator/priv/models/
mv coco_classes.json apps/video_annotator/priv/models/

# Verify
ls -lh apps/video_annotator/priv/models/
# Expected:
# yolo11n.onnx (~6 MB)
# coco_classes.json (~2 KB)
```

**Why YOLOv11n?**
- ✅ Latest YOLO architecture (2024)
- ✅ Best accuracy for size (39.5% mAP on COCO)
- ✅ Good performance (~8 FPS on Raspberry Pi 5)
- ✅ Supports latest features (pose, segmentation, etc.)

**Alternative:** For pre-converted models (no export needed), see YOLOX option in [model-export-guide.md](model-export-guide.md)

---

## Step 2: Create VideoAnnotator App (10 minutes)

### Create New Application

```bash
# From repository root
cd apps
mix new video_annotator --sup
cd video_annotator
```

### Add Dependencies

Edit `mix.exs`:

```elixir
defp deps do
  [
    # YOLO inference
    {:yolo_elixir, "~> 0.3"},

    # Numerical computing
    {:nx, "~> 0.7"},
    {:exla, "~> 0.7"},  # XLA backend for Nx

    # ONNX Runtime with CoreML
    {:ortex, "~> 0.1"},

    # Video processing
    {:membrane_core, "~> 1.0"},
    {:membrane_camera_capture_plugin, "~> 0.7"},
    {:membrane_h264_ffmpeg_plugin, "~> 0.32"},
    {:membrane_file_plugin, "~> 0.17"},

    # Image processing for overlay
    {:vix, "~> 0.26"},

    # Utilities
    {:telemetry, "~> 1.2"}
  ]
end
```

### Install Dependencies

```bash
mix deps.get
```

**Note:** First run may take 5-10 minutes to compile EXLA with XLA support.

---

## Step 3: Configure Ortex for CoreML (2 minutes)

### Set Environment Variable

```bash
# Add to ~/.zshrc or ~/.bashrc
export ORTEX_FEATURES=coreml
```

Or for this session only:

```bash
export ORTEX_FEATURES=coreml
```

### Verify CoreML Support

```bash
iex -S mix
```

```elixir
# In IEx
{:ok, model} = Ortex.load("../../yolo11n.onnx")
# Should load without errors
```

---

## Step 4: Create Simple Inference Test (15 minutes)

### Create Test Module

**File:** `lib/video_annotator/inference_test.ex`

```elixir
defmodule VideoAnnotator.InferenceTest do
  @moduledoc """
  Simple test to verify YOLO inference works with yolo_elixir.
  Uses YOLOv11n model.
  """

  require Logger

  def run_test do
    Logger.info("Loading YOLOv11n model...")

    # Load YOLOv11 model (Ultralytics implementation)
    model = YOLO.load(
      model_impl: YOLO.Models.Ultralytics,
      model_path: "priv/models/yolo11n.onnx",
      classes_path: "priv/models/coco_classes.json"
    )

    Logger.info("Model loaded successfully!")
    Logger.info("Model info: #{inspect(model)}")

    # Create test image (YOLOv11n expects 640x640)
    test_image = Nx.random_uniform({640, 640, 3})

    Logger.info("Running inference on test image...")

    # Run detection
    detections = model
      |> YOLO.detect(test_image)
      |> YOLO.to_detected_objects(model.classes)

    Logger.info("Detections: #{inspect(detections)}")
    Logger.info("✓ Inference test complete!")

    {:ok, model, detections}
  end
end
```

**Note:** Models are in `priv/models/` from Step 1.

### Run Test

```bash
iex -S mix
```

```elixir
VideoAnnotator.InferenceTest.run_test()
```

**Expected Output:**
```
[info] Loading YOLO model...
[info] Model loaded successfully!
[info] Running inference on test image...
[info] Detections: []
[info] ✓ Inference test complete!
```

---

## Step 5: Add Webcam Capture (10 minutes)

### Create Simple Pipeline

**File:** `lib/video_annotator/demo_pipeline.ex`

```elixir
defmodule VideoAnnotator.DemoPipeline do
  @moduledoc """
  Simple demo pipeline: Webcam → Display
  Phase 0: Just capture and display, no annotation yet.
  """

  use Membrane.Pipeline
  require Membrane.Logger

  @impl true
  def handle_init(_ctx, _opts) do
    Membrane.Logger.info("Starting demo pipeline with webcam")

    spec = [
      # Webcam source (FFmpeg-based on macOS)
      child(:camera, %Membrane.CameraCapture.Source{
        camera_id: 0,  # Default webcam
        width: 640,
        height: 480,
        framerate: {30, 1}
      })
      # For now, just write to file (TODO: add display/RTSP)
      |> child(:sink, %Membrane.File.Sink{
        location: "/tmp/webcam_output.h264"
      })
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification(notification, element, _ctx, state) do
    Membrane.Logger.debug("Notification from #{inspect(element)}: #{inspect(notification)}")
    {[], state}
  end
end
```

### Test Webcam Capture

```bash
iex -S mix
```

```elixir
{:ok, pipeline} = VideoAnnotator.DemoPipeline.start_link()

# Let it run for 5 seconds
Process.sleep(5000)

# Check output file
File.stat!("/tmp/webcam_output.h264")
```

**Expected:** File exists with video data (should be >0 bytes)

### View Captured Video

```bash
# Install VLC if not already installed
brew install --cask vlc

# Play captured video
vlc /tmp/webcam_output.h264
```

---

## Step 6: Add Annotation Overlay (10 minutes)

### Create Annotation Filter

**File:** `lib/video_annotator/simple_annotator.ex`

```elixir
defmodule VideoAnnotator.SimpleAnnotator do
  @moduledoc """
  Simple annotation: Run YOLO on frames and overlay bounding boxes.
  Phase 0: Simplified version for quick testing.
  """

  use Membrane.Filter
  require Membrane.Logger

  def_input_pad :input,
    accepted_format: Membrane.RawVideo

  def_output_pad :output,
    accepted_format: Membrane.RawVideo

  def_options model: [
    spec: map(),
    description: "YOLO model from YOLO.load()"
  ]

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      model: opts.model,
      frame_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    # Run inference every 10 frames for performance
    if rem(state.frame_count, 10) == 0 do
      # TODO: Convert buffer to Nx tensor
      # TODO: Run YOLO.detect()
      # TODO: Overlay bounding boxes with Vix
      Membrane.Logger.debug("Running inference on frame #{state.frame_count}")
    end

    # For now, just pass through
    new_state = %{state | frame_count: state.frame_count + 1}
    {[buffer: {:output, buffer}], new_state}
  end
end
```

---

## Step 7: Verify Everything Works (5 minutes)

### Full Integration Test

```bash
iex -S mix
```

```elixir
# 1. Load YOLOv11 model
model = YOLO.load(
  model_impl: YOLO.Models.Ultralytics,
  model_path: "priv/models/yolo11n.onnx",
  classes_path: "priv/models/coco_classes.json"
)

# 2. Create test tensor (640x640 for YOLOv11n)
test_frame = Nx.random_uniform({640, 640, 3})

# 3. Run detection
detections = model
  |> YOLO.detect(test_frame)
  |> YOLO.to_detected_objects(model.classes)

# 4. Verify
IO.puts("✓ Model loaded")
IO.puts("✓ Inference works")
IO.puts("✓ Detections: #{inspect(detections)}")
IO.puts("✓ Ready for webcam integration!")
```

---

## Success Criteria

You've successfully completed Phase 0 when:

- [x] YOLOv11n model exported to ONNX format
- [x] yolo_elixir loads model without errors
- [x] Inference runs on test images
- [x] Webcam capture works with Membrane
- [x] Can see captured video in VLC
- [x] CoreML acceleration enabled (check with `System.get_env("ORTEX_FEATURES")`)

**Bonus:**
- [ ] Real-time detection working on webcam feed
- [ ] Bounding boxes overlaid on live video
- [ ] Can switch between YOLOv11n and YOLOv11s models

---

## Next Steps

### Immediate (Finish Phase 0)
1. **Add real-time display:** Stream to browser or use SDL for live video
2. **Overlay detections:** Use Vix to draw bounding boxes on frames
3. **Test with real objects:** Point webcam at objects, verify detections
4. **Measure FPS:** Add telemetry to track inference performance

### Phase 1 (Week 2-3)
1. Refactor into proper application structure
2. Add configuration for model paths
3. Create platform-agnostic camera source (macOS vs Pi)
4. Start integration with existing video-streamer

---

## Troubleshooting

### Model Loading Fails

**Error:** `File not found: priv/models/yolo11n.onnx`

**Solution:** Verify file exists and path is correct:
```bash
ls -lh priv/models/yolo11n.onnx
```

### CoreML Not Working

**Error:** `CoreML acceleration not available`

**Solution:**
1. Check environment variable: `echo $ORTEX_FEATURES`
2. Verify macOS version: `sw_vers` (need Ventura 13+)
3. Recompile Ortex: `mix deps.clean ortex && mix deps.get`

### Webcam Not Detected

**Error:** `Camera not found: 0`

**Solution:**
1. Check camera access: System Settings → Privacy & Security → Camera
2. Grant terminal access to camera
3. Try different camera ID: `camera_id: 1`

### FFmpeg Not Found

**Error:** `FFmpeg binary not found`

**Solution:**
```bash
brew install ffmpeg
which ffmpeg  # Verify installation
```

### Slow Inference

**Issue:** Inference taking >500ms per frame

**Solution:**
1. Verify CoreML enabled: `export ORTEX_FEATURES=coreml`
2. Use smaller model: Try `yolo11n` (nano) instead of larger variants
3. Reduce image size: Use 416x416 instead of 640x640
4. Check Activity Monitor for CPU usage

---

## Performance Benchmarks

Expected performance on macOS:

| Hardware | Model | Input Size | FPS | Inference Time |
|----------|-------|------------|-----|----------------|
| M1 Mac (CoreML) | yolo11n | 640x640 | 15-20 | ~50ms |
| M2 Mac (CoreML) | yolo11n | 640x640 | 20-25 | ~40ms |
| Intel Mac (CPU) | yolo11n | 640x640 | 5-8 | ~150ms |

---

## Resources

- [yolo_elixir Documentation](https://hexdocs.pm/yolo_elixir)
- [Membrane Framework Docs](https://hexdocs.pm/membrane_core)
- [Ortex GitHub](https://github.com/elixir-nx/ortex)
- [Model Export Guide](model-export-guide.md)
- [Full Implementation Plan](implementation_plan.md)

---

**Phase 0 Owner:** TBD
**Estimated Duration:** 1 hour (initial setup) + ongoing development
**Last Updated:** 2025-10-25
