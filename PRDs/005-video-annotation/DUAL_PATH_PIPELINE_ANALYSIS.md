# Dual-Path Pipeline Analysis: Full FPS Preview + Async Annotations

**Date**: October 26, 2025
**Context**: User wants smooth 30 FPS preview for drone piloting with slower-rate annotations overlaid

---

## Problem Statement

**Current Architecture (Phase 0)**:
- Camera: 30 FPS
- Processing: 4 FPS (with EMLX) or 2 FPS (RPi estimated with ACL)
- Preview: Shows only processed frames (4 FPS) with annotations

**Issue**: Laggy 4 FPS preview is **not acceptable for drone piloting**
- Pilot needs smooth video for navigation
- Delayed annotations are acceptable
- Current approach sacrifices preview smoothness for annotation rate

---

## Proposed Solution: Dual-Path Architecture

### High-Level Design

```
┌────────────────────────────────────────────────────────────┐
│                      Camera Source                          │
│                       (30 FPS NV12)                         │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       │ Tee (split stream)
                       │
        ┌──────────────┴──────────────┐
        │                              │
        ▼                              ▼
┌───────────────┐            ┌─────────────────┐
│ Preview Path  │            │ Detection Path  │
│   (30 FPS)    │            │    (4 FPS)      │
├───────────────┤            ├─────────────────┤
│ No processing │            │ YOLO detection  │
│ Send to web   │            │ Generate boxes  │
│ immediately   │            │ Send metadata   │
└───────┬───────┘            └────────┬────────┘
        │                              │
        │                              │
        └──────────────┬───────────────┘
                       ▼
                ┌──────────────┐
                │ Web Preview  │
                │   Overlay    │
                ├──────────────┤
                │ • Show latest frame (30 FPS)
                │ • Draw cached annotations
                │ • Update boxes when new detection
                └──────────────┘
```

### Key Concepts

1. **Tee splits camera stream** into two independent paths
2. **Preview path**: Pass-through at 30 FPS, minimal processing
3. **Detection path**: Toilet + time-based skipping (4 FPS on macOS, 2 FPS on RPi)
4. **Web overlay**: Client-side combines latest frame + latest detections

---

## Architecture Options

### Option A: Server-Side Overlay (Elixir/Membrane)

**Pipeline**:
```elixir
child(:camera, CameraCapture)
|> child(:tee, Membrane.Tee.Parallel)

# Preview path (30 FPS)
get_child(:tee)
|> via_out(Pad.ref(:output, 0))
|> child(:preview_converter, NV12ToRGB)
|> child(:preview_jpeg, JPEGEncoder)
|> child(:preview_buffer, LatestFrameBuffer)  # ETS-based, 1 frame

# Detection path (4 FPS)
get_child(:tee)
|> via_out(Pad.ref(:output, 1))
|> via_in(:input, toilet_capacity: 1)
|> child(:yolo, YoloDetector)  # Outputs detections only (no image)
|> child(:detection_buffer, LatestDetectionBuffer)  # ETS-based

# Overlay path (client requests combined frame)
# On HTTP request: read latest frame + latest detections, draw boxes, return JPEG
```

**Pros**:
- ✅ Server does all work
- ✅ Client is simple (just displays JPEG)
- ✅ Annotations drawn server-side (consistent)

**Cons**:
- ⚠️  Need to synchronize frame + detection buffers
- ⚠️  Server draws boxes on every HTTP request (CPU cost)
- ⚠️  More complex Membrane pipeline

**Complexity**: **Medium** (doable in Membrane)

---

### Option B: Client-Side Overlay (JavaScript/Canvas)

**Pipeline**:
```elixir
child(:camera, CameraCapture)
|> child(:tee, Membrane.Tee.Parallel)

# Preview path (30 FPS) - send raw frames
get_child(:tee)
|> via_out(Pad.ref(:output, 0))
|> child(:preview_jpeg, JPEGEncoder)
|> via_in(:input)
|> child(:preview_sink, WebPreviewSink)  # Stream MJPEG

# Detection path (4 FPS) - send JSON detections
get_child(:tee)
|> via_out(Pad.ref(:output, 1))
|> via_in(:input, toilet_capacity: 1)
|> child(:yolo, YoloDetector)  # Outputs detections only
|> child(:detection_sink, WebSocketSink)  # Stream JSON
```

**Client** (JavaScript):
```javascript
// MJPEG stream for video (30 FPS)
const img = document.getElementById('video');
img.src = 'http://localhost:4001/stream';

// WebSocket for detections (4 FPS)
const ws = new WebSocket('ws://localhost:4001/detections');
let latestDetections = [];

ws.onmessage = (event) => {
  latestDetections = JSON.parse(event.data);
};

// Canvas overlay (redraws at 30 FPS)
const canvas = document.getElementById('overlay');
const ctx = canvas.getContext('2d');

function drawOverlay() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  // Draw bounding boxes from latest detections
  latestDetections.forEach(det => {
    ctx.strokeStyle = 'green';
    ctx.lineWidth = 2;
    ctx.strokeRect(det.x, det.y, det.w, det.h);

    // Label
    ctx.fillStyle = 'green';
    ctx.fillText(`${det.class} ${det.confidence}`, det.x, det.y - 5);
  });

  requestAnimationFrame(drawOverlay);
}
drawOverlay();
```

**Pros**:
- ✅ Simpler Membrane pipeline (just two sinks)
- ✅ Client does overlay work (offloads server)
- ✅ Smooth 30 FPS video guaranteed
- ✅ Easy to adjust overlay style

**Cons**:
- ⚠️  Requires JavaScript client (not just MJPEG viewer)
- ⚠️  Need WebSocket support
- ⚠️  More complex client

**Complexity**: **Medium** (simpler pipeline, more complex client)

---

### Option C: Hybrid - Annotated Keyframes + Raw Frames

**Pipeline**:
```elixir
child(:camera, CameraCapture)
|> child(:tee, Membrane.Tee.Parallel)

# Fast path: Raw JPEG stream (30 FPS)
get_child(:tee)
|> via_out(Pad.ref(:output, 0))
|> child(:jpeg, JPEGEncoder)
|> child(:preview_sink, MJPEGSink)

# Slow path: Annotated keyframes (4 FPS)
get_child(:tee)
|> via_out(Pad.ref(:output, 1))
|> via_in(:input, toilet_capacity: 1)
|> child(:yolo, YoloDetector)  # Draws annotations
|> child(:keyframe_buffer, LatestAnnotatedFrame)  # ETS

# Client: Show fast stream, overlay keyframe annotations
```

**Client**:
- Display 30 FPS MJPEG stream
- Poll `/latest_annotations` every 250ms
- Extract bounding boxes from annotated keyframe
- Draw boxes on live stream

**Pros**:
- ✅ Best of both worlds
- ✅ No WebSocket needed
- ✅ Simple client (HTTP only)

**Cons**:
- ⚠️  Client needs to extract box positions from annotated image (OCR? metadata sidecar?)
- ⚠️  More complex than A or B

**Complexity**: **Medium-High**

---

## Recommended Approach: Option B (Client-Side Overlay)

### Rationale

1. **Simplest pipeline** - Just add Tee and two sinks
2. **Best performance** - Server sends raw data, client renders
3. **Most flexible** - Client can customize overlay appearance
4. **Proven pattern** - MJPEG + WebSocket is standard web stack

### Implementation Plan

#### Phase 1: Membrane Pipeline Changes

**File**: `apps/video_annotator/lib/video_annotator/pipeline.ex`

```elixir
defmodule VideoAnnotator.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      child(:camera, %Membrane.CameraCapture{
        device: opts[:camera],
        framerate: 30
      })
      |> child(:tee, Membrane.Tee.Parallel)
    ]

    # Preview path (30 FPS)
    spec = spec ++ [
      get_child(:tee)
      |> via_out(Pad.ref(:output, 0))
      |> child(:preview_converter, %NV12ToRGBConverter{})
      |> child(:preview_jpeg, %JPEGEncoder{quality: 85})
      |> child(:preview_sink, %WebPreview.FrameSink{})
    ]

    # Detection path (4 FPS on macOS, 2 FPS on RPi)
    spec = spec ++ [
      get_child(:tee)
      |> via_out(Pad.ref(:output, 1))
      |> via_in(:input, toilet_capacity: 1)  # Drop old frames
      |> child(:yolo_detector, %VideoAnnotator.YoloDetector{
        model_path: opts[:model_path],
        classes_path: opts[:classes_path],
        output_type: :detections_only  # Don't draw on image!
      })
      |> child(:detection_sink, %WebPreview.DetectionSink{})
    ]

    {[spec: spec], %{}}
  end
end
```

#### Phase 2: YoloDetector Changes

**File**: `apps/video_annotator/lib/video_annotator/yolo_detector.ex`

Add option to output detections without drawing:

```elixir
def_options output_type: [
  spec: :full | :detections_only,
  default: :full,
  description: "Output annotated image (:full) or just detections (:detections_only)"
]

@impl true
def handle_buffer(:input, buffer, ctx, state) do
  # ... run detection ...

  case state.output_type do
    :full ->
      # Current behavior: draw annotations and output image
      annotated_buffer = draw_detections(buffer, detections, state.classes)
      {[buffer: {:output, annotated_buffer}], new_state}

    :detections_only ->
      # New behavior: output detection metadata only
      detection_buffer = %{
        buffer
        | metadata: Map.put(buffer.metadata || %{}, :detections, detections)
      }
      {[buffer: {:output, detection_buffer}], new_state}
  end
end
```

#### Phase 3: Web Preview Sinks

**File**: `apps/video_annotator/lib/video_annotator/web_preview/frame_sink.ex`

```elixir
defmodule VideoAnnotator.WebPreview.FrameSink do
  use Membrane.Sink

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    # Store latest frame in ETS (30 FPS updates)
    :ets.insert(:preview_frames, {:latest, buffer.payload})
    {[], state}
  end
end
```

**File**: `apps/video_annotator/lib/video_annotator/web_preview/detection_sink.ex`

```elixir
defmodule VideoAnnotator.WebPreview.DetectionSink do
  use Membrane.Sink

  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    detections = buffer.metadata[:detections] || []

    # Store latest detections in ETS (4 FPS updates)
    :ets.insert(:preview_detections, {:latest, detections})

    # Broadcast to WebSocket clients
    WebPreview.Server.broadcast_detections(detections)

    {[], state}
  end
end
```

#### Phase 4: Web Server Updates

**File**: `apps/video_annotator/lib/video_annotator/web_preview.ex`

Add WebSocket endpoint:

```elixir
defmodule VideoAnnotator.WebPreview do
  use Plug.Router

  plug :match
  plug :dispatch

  # MJPEG stream (30 FPS)
  get "/stream" do
    conn
    |> put_resp_content_type("multipart/x-mixed-replace; boundary=frame")
    |> send_chunked(200)
    |> stream_frames()
  end

  # WebSocket for detections (4 FPS)
  get "/detections" do
    conn
    |> WebSockAdapter.upgrade(VideoAnnotator.WebPreview.DetectionSocket, [], [])
  end

  # HTML page with canvas overlay
  get "/" do
    send_resp(conn, 200, html_with_overlay())
  end

  defp stream_frames(conn) do
    case :ets.lookup(:preview_frames, :latest) do
      [{:latest, jpeg}] ->
        {:ok, conn} = chunk(conn, "--frame\r\nContent-Type: image/jpeg\r\n\r\n")
        {:ok, conn} = chunk(conn, jpeg)
        {:ok, conn} = chunk(conn, "\r\n")
        Process.sleep(33)  # ~30 FPS
        stream_frames(conn)
      [] ->
        Process.sleep(10)
        stream_frames(conn)
    end
  end
end
```

**File**: `apps/video_annotator/lib/video_annotator/web_preview/detection_socket.ex`

```elixir
defmodule VideoAnnotator.WebPreview.DetectionSocket do
  @behaviour WebSock

  @impl true
  def init(_opts) do
    # Subscribe to detection broadcasts
    Phoenix.PubSub.subscribe(:detections)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:detections, detections}, state) do
    json = Jason.encode!(detections)
    {:push, {:text, json}, state}
  end
end
```

#### Phase 5: HTML Client with Canvas Overlay

**File**: `apps/video_annotator/lib/video_annotator/web_preview.ex` (HTML template)

```html
<!DOCTYPE html>
<html>
<head>
  <title>Video Annotator - Live Preview</title>
  <style>
    body { margin: 0; background: #000; }
    #container { position: relative; width: 100vw; height: 100vh; }
    #video { position: absolute; width: 100%; height: 100%; object-fit: contain; }
    #overlay { position: absolute; width: 100%; height: 100%; pointer-events: none; }
    #stats { position: absolute; top: 10px; left: 10px; color: white;
             background: rgba(0,0,0,0.7); padding: 10px; font-family: monospace; }
  </style>
</head>
<body>
  <div id="container">
    <img id="video" src="/stream" />
    <canvas id="overlay"></canvas>
    <div id="stats">
      <div>Preview FPS: <span id="preview-fps">0</span></div>
      <div>Detection FPS: <span id="detection-fps">0</span></div>
      <div>Detections: <span id="detection-count">0</span></div>
    </div>
  </div>

  <script>
    const video = document.getElementById('video');
    const canvas = document.getElementById('overlay');
    const ctx = canvas.getContext('2d');

    let latestDetections = [];
    let previewFps = 0;
    let detectionFps = 0;

    // WebSocket for detections
    const ws = new WebSocket('ws://localhost:4001/detections');
    ws.onmessage = (event) => {
      latestDetections = JSON.parse(event.data);
      updateStats();
    };

    // Resize canvas to match video
    function resizeCanvas() {
      canvas.width = video.clientWidth;
      canvas.height = video.clientHeight;
    }
    video.addEventListener('load', resizeCanvas);
    window.addEventListener('resize', resizeCanvas);

    // Draw overlay at 30 FPS
    function drawOverlay() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      const scaleX = canvas.width / 640;   // Assuming 640x640 model input
      const scaleY = canvas.height / 640;

      latestDetections.forEach(det => {
        const x = det.bbox[0] * scaleX;
        const y = det.bbox[1] * scaleY;
        const w = det.bbox[2] * scaleX;
        const h = det.bbox[3] * scaleY;

        // Draw bounding box
        ctx.strokeStyle = '#00ff00';
        ctx.lineWidth = 3;
        ctx.strokeRect(x, y, w, h);

        // Draw label background
        const label = `${det.class} ${(det.confidence * 100).toFixed(0)}%`;
        ctx.font = '16px monospace';
        const textWidth = ctx.measureText(label).width;

        ctx.fillStyle = 'rgba(0, 255, 0, 0.8)';
        ctx.fillRect(x, y - 25, textWidth + 10, 25);

        // Draw label text
        ctx.fillStyle = '#000';
        ctx.fillText(label, x + 5, y - 7);
      });

      requestAnimationFrame(drawOverlay);
    }

    drawOverlay();

    function updateStats() {
      document.getElementById('detection-count').textContent = latestDetections.length;
      // Calculate FPS from timestamps...
    }
  </script>
</body>
</html>
```

---

## Complexity Assessment

### Membrane Pipeline Changes
**Complexity**: **Low-Medium**
- Add Tee (built-in Membrane component)
- Add two sinks (simple custom elements)
- Modify YoloDetector output option

**Estimated effort**: 1-2 days

### Web Server Changes
**Complexity**: **Medium**
- Add WebSocket support (need `websock_adapter` dep)
- Implement detection broadcast
- HTML/JavaScript client

**Estimated effort**: 2-3 days

### Testing & Integration
**Complexity**: **Low**
- Test on macOS first
- Deploy to RPi
- Tune performance

**Estimated effort**: 1 day

**Total**: 4-6 days

---

## Performance Analysis

### Current (Phase 0)
- Preview FPS: **4 FPS** (laggy for piloting)
- Detection rate: 4 FPS
- Latency: ~270ms

### With Dual-Path
- Preview FPS: **30 FPS** (smooth for piloting!) ✅
- Detection rate: 4 FPS (same)
- Annotation latency: ~270ms (acceptable delay)

### Network Bandwidth

**MJPEG stream (30 FPS)**:
- Resolution: 640x640
- Quality: 85%
- Size per frame: ~50-80 KB
- Bandwidth: 50 KB × 30 = **1.5 MB/s** (12 Mbps)

**WebSocket (4 FPS)**:
- JSON detections: ~1 KB per frame
- Bandwidth: 1 KB × 4 = **4 KB/s** (negligible)

**Total**: ~12 Mbps (acceptable on local network or WiFi)

---

## Pros & Cons Summary

### Pros ✅
- **Smooth 30 FPS preview** - Critical for drone piloting
- **Annotations still visible** - Just slightly delayed
- **Better user experience** - Pilot can navigate + see detections
- **Moderate complexity** - Doable in 4-6 days
- **Reuses Phase 0 code** - YoloDetector mostly unchanged

### Cons ⚠️
- **More complex than current** - Need WebSocket + client-side rendering
- **Higher bandwidth** - 12 Mbps vs 0.5 Mbps (but local network OK)
- **Requires JavaScript client** - Can't use simple MJPEG viewer
- **Annotation delay** - 250-500ms behind video (acceptable?)

---

## Decision Matrix

| Factor | Current (4 FPS annotated) | Dual-Path (30 FPS + overlay) |
|--------|---------------------------|------------------------------|
| **Piloting UX** | ❌ Too laggy | ✅ Smooth |
| **Annotation visibility** | ✅ Always visible | ✅ Visible (slight delay) |
| **Implementation** | ✅ Simple (done!) | ⚠️  4-6 days work |
| **Bandwidth** | ✅ Low (0.5 Mbps) | ⚠️  Higher (12 Mbps) |
| **Client complexity** | ✅ Simple MJPEG | ⚠️  Need WebSocket |
| **Scalability** | ✅ Works anywhere | ⚠️  Local network only |

---

## Recommendation

### For Development (macOS): Keep Current
- Current 4 FPS is acceptable for development
- Simpler to maintain
- Already working

### For Production (Drone): Implement Dual-Path ⭐
- **Critical for drone operation** - pilot needs smooth video
- 250-500ms annotation delay is acceptable
- Worth the 4-6 days of work

### Phased Approach

**Phase 0** (Current): ✅ Done
- Simple 4 FPS annotated preview
- Good for development

**Phase 1.5** (Optional): Dual-path for production
- Implement after ACL integration
- Only if drone piloting requires it
- Can be separate branch/feature flag

---

## Alternative: Simple Compromise

If dual-path is too complex, consider:

**Show unannotated 30 FPS + latest detection count overlay**

```elixir
# Simple: Stream raw frames at 30 FPS
# Overlay just detection count text (no boxes)

Preview: "30 FPS | 3 objects detected"
```

**Pros**:
- Much simpler (1 day work)
- Smooth video
- Pilot knows objects detected

**Cons**:
- No bounding boxes visible
- Less useful than full annotations

---

## Conclusion

✅ **Dual-path pipeline is feasible and valuable for drone operation**

**Recommendation**:
1. **Complete Phase 1 with ACL first** (get RPi working)
2. **Evaluate piloting UX** (is 4 FPS acceptable?)
3. **If needed**: Implement dual-path as Phase 1.5
4. **Timeline**: +4-6 days if implemented

The architecture is **not overly complicated** - Membrane Tee + WebSocket is standard. The benefit to drone piloting UX is **significant** (4 FPS → 30 FPS preview).

**Next decision**: Prioritize ACL or dual-path first?

My suggestion: **ACL first** (get 2-4 FPS on RPi), then **dual-path** (make it usable for piloting).
