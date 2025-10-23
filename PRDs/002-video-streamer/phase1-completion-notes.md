# Phase 1 Completion Notes - Video Streamer

**Date:** 2025-10-22
**Status:** ✅ COMPLETE
**Tests Passing:** 1-5 (all basic pipeline tests)

---

## Summary

Phase 1 of the video streamer implementation is **complete and working** on Raspberry Pi hardware. The pipeline successfully captures video from the camera, processes it through H.264 parsing and RTP payloading, and outputs to a sink.

---

## Issues Encountered & Fixes Applied

### 1. Unlinked Static Pad Error

**Error:**
```
Child :rtp_payloader has static pad :output, but it is not linked in spec
```

**Root Cause:** The pipeline ended at the RTP payloader without connecting its output to anything.

**Fix:** Added `Membrane.Fake.Sink.Buffers` as a temporary sink for Phase 1 testing.
- Added `membrane_fake_plugin` dependency
- Connected fake sink to consume RTP packets
- This will be replaced with actual RTSP output in Phase 2

**Files Modified:**
- `apps/video_streamer/mix.exs` - Added dependency
- `apps/video_streamer/lib/video_streamer/pipeline.ex` - Added sink

---

### 2. CaseClauseError - Pipeline Start Return Value

**Error:**
```
no case clause matching: {:ok, #PID<0.274.0>, #PID<0.276.0>}
```

**Root Cause:** `Membrane.Pipeline.start_link/2` returns a 3-tuple `{:ok, supervisor_pid, pipeline_pid}`, but the code was pattern matching for a 2-tuple `{:ok, pipeline_pid}`.

**Fix:** Updated all pattern matches in PipelineManager to handle the 3-tuple correctly.

**Files Modified:**
- `apps/video_streamer/lib/video_streamer/pipeline_manager.ex`
  - Line 65: `handle_call(:start_streaming)`
  - Line 96: `handle_call({:restart_streaming})`
  - Line 116: `handle_info(:auto_start)`

---

### 3. Camera Binary Not Found (Exit Status 127)

**Error:**
```
Max retries exceeded, camera failed to open, exit status: 127
```

**Root Cause:** The `membrane_rpicam_plugin` was hardcoded to use `libcamera-vid`, but newer Raspberry Pi OS uses `rpicam-vid`.

**Fix:** Internalized the plugin with automatic binary detection.
- Created `lib/membrane_rpicam/source.ex` based on v0.1.5
- Added automatic detection of `rpicam-vid` vs `libcamera-vid`
- Falls back to older binary if newer one not found
- Logs which binary is being used

**Files Created:**
- `apps/video_streamer/lib/membrane_rpicam/source.ex`
- `apps/video_streamer/lib/membrane_rpicam/README.md`

**Files Modified:**
- `apps/video_streamer/mix.exs` - Removed external dependency

---

### 4. libav Output Format Error (Exit Status 255)

**Error:**
```
Unable to choose an output format for '-'
ERROR: *** libav: cannot allocate output context, try setting with --libav-format ***
```

**Root Cause:** When outputting to stdout (`-o -`), `rpicam-vid` requires explicit codec and format parameters.

**Fix:** Added `--codec h264 --libav-format h264` to the command.

**Files Modified:**
- `apps/video_streamer/lib/membrane_rpicam/source.ex` - Line 145

**Command Before:**
```bash
rpicam-vid -t 0 --framerate 30.0 --width 1280 --height 720 -o -
```

**Command After:**
```bash
rpicam-vid -t 0 --codec h264 --libav-format h264 --framerate 30.0 --width 1280 --height 720 -o -
```

---

### 5. Stream Format Alignment Mismatch

**Error:**
```
Stream format alignment: :au is not matching accepted format pattern alignment: :nalu
```

**Root Cause:** The H.264 parser was outputting Access Units (complete frames), but the RTP payloader expects NALUs (Network Abstraction Layer Units).

**Fix:** Configured the H.264 parser with explicit NALU alignment and timestamp generation.

**Files Modified:**
- `apps/video_streamer/lib/video_streamer/pipeline.ex` - Lines 22-25

**Configuration Added:**
```elixir
child(:h264_parser, %Membrane.H264.Parser{
  output_alignment: :nalu,
  generate_best_effort_timestamps: %{framerate: {30, 1}}
})
```

---

### 6. Verbose Frame Statistics Output

**Issue:** `rpicam-vid` outputs frame statistics to stdout by default:
```
#501 (30.01 fps) exp 33251.00 ag 8.26 dg 1.01
#502 (30.00 fps) exp 33251.00 ag 8.00 dg 1.02
...
```

**Fix:** Added configurable `verbose` option that defaults to `false`.
- Added `verbose` parameter to `Membrane.Rpicam.Source`
- Added `--nopreview` flag when `verbose: false`
- Made it configurable via application config

**Files Modified:**
- `apps/video_streamer/lib/membrane_rpicam/source.ex` - Added option
- `apps/video_streamer/lib/video_streamer/pipeline.ex` - Read from config
- `apps/video_streamer/config/config.exs` - Added default
- `apps/video_streamer/config/dev.exs` - Added override

---

## Key Architectural Decisions

### Internalized Camera Plugin

**Decision:** Internalize `membrane_rpicam_plugin` into the project.

**Rationale:**
- Single file dependency (~180 lines)
- Needed multiple fixes for compatibility
- Easier to maintain and modify
- No waiting for upstream fixes
- Preserved Apache 2.0 license and attribution

**Benefits:**
- ✅ Full control over camera integration
- ✅ No dependency on external plugin updates
- ✅ Can make project-specific optimizations
- ✅ Clear documentation of changes

---

## Current Pipeline Flow

```
┌─────────────────┐
│  rpicam-vid     │ (Camera capture + H.264 encoding via GPU)
│  (Membrane.     │
│   Rpicam.Source)│
└────────┬────────┘
         │ H.264 bytestream
         ▼
┌─────────────────┐
│  H.264 Parser   │ (Parse into NALUs + timestamps)
│  (alignment:    │
│   :nalu)        │
└────────┬────────┘
         │ Individual NALUs
         ▼
┌─────────────────┐
│  RTP Payloader  │ (Package NALUs into RTP packets)
│  (Membrane.RTP. │
│   H264.Payloader)│
└────────┬────────┘
         │ RTP packets
         ▼
┌─────────────────┐
│  Fake Sink      │ (Drops packets - temporary for Phase 1)
│  (will be RTSP  │
│   in Phase 2)   │
└─────────────────┘
```

---

## Configuration Options

### Camera Settings

```elixir
config :video_streamer,
  camera: [
    width: 1280,              # Resolution width
    height: 720,              # Resolution height
    framerate: 30,            # Frames per second
    verbose: false            # Show frame statistics (for debugging)
  ]
```

### How to Enable Verbose Mode

For debugging camera issues, set `verbose: true`:

```elixir
config :video_streamer,
  camera: [
    width: 1280,
    height: 720,
    framerate: 30,
    verbose: true  # Shows: #501 (30.01 fps) exp 33251.00 ag 8.26 dg 1.01
  ]
```

---

## Testing Results

### Test 1: Camera Detection
✅ **PASS** - Camera detected via `rpicam-vid --list-cameras`

### Test 2: H.264 Encoding
✅ **PASS** - `rpicam-vid` successfully encodes H.264 to file

### Test 3: GPU Memory
✅ **PASS** - GPU memory allocation verified

### Test 4: Compilation
✅ **PASS** - Application compiles without errors

### Test 5: Basic Pipeline
✅ **PASS** - Pipeline runs successfully on hardware
- Application starts
- Camera opens and captures
- H.264 parsing works
- RTP payloading works
- Pipeline status: `:running`

---

## Setup Requirements

### On Raspberry Pi

```bash
# 1. Install rpicam-apps
sudo apt update
sudo apt install -y rpicam-apps

# 2. Verify installation
rpicam-vid --version

# 3. Enable camera (if needed)
sudo raspi-config
# Navigate to: Interface Options -> Camera -> Enable

# 4. Add user to video group
sudo usermod -a -G video $USER
# Log out and back in for changes to take effect

# 5. Test camera
rpicam-vid -t 5000 -o /dev/null
```

### No Symlinks Required

The internalized camera module automatically detects which binary is available:
- Tries `rpicam-vid` first (newer Raspberry Pi OS)
- Falls back to `libcamera-vid` (older systems)
- Logs which binary is being used

---

## Files Modified/Created

### New Files
- `apps/video_streamer/lib/membrane_rpicam/source.ex` - Internalized camera source
- `apps/video_streamer/lib/membrane_rpicam/README.md` - Documentation
- `PRDs/002-video-streamer/phase1-completion-notes.md` - This file

### Modified Files
- `apps/video_streamer/lib/video_streamer/pipeline.ex` - H.264 parser config, fake sink
- `apps/video_streamer/lib/video_streamer/pipeline_manager.ex` - Fixed pattern matching
- `apps/video_streamer/mix.exs` - Removed external plugin, added fake plugin
- `apps/video_streamer/config/config.exs` - Added verbose option
- `apps/video_streamer/config/dev.exs` - Added verbose option
- `PRDs/002-video-streamer/implementation_checklist.md` - Updated progress

---

## Next Steps: Phase 2

Phase 1 is complete! Ready to proceed with **Phase 2: RTSP Server Implementation**

Phase 2 will:
1. Replace the fake sink with actual RTSP server
2. Implement RTSP protocol handlers
3. Generate SDP responses
4. Handle multiple client sessions
5. Enable VLC/ffplay viewing

See [implementation_checklist.md](implementation_checklist.md#phase-2-rtsp-server-implementation-weeks-3-4) for Phase 2 tasks.

---

## Performance Notes

### Observed Metrics
- **Camera**: Opens successfully in <2s
- **Pipeline startup**: <3s from application start to `:running`
- **Framerate**: Stable 30 fps
- **Output**: Clean logs (no frame spam with `verbose: false`)

### Resource Usage
(Will be measured in Phase 5 - Performance Testing)

---

## Acknowledgments

### Dependencies Used
- **Membrane Framework** - Media processing framework
- **membrane_rpicam_plugin** (v0.1.5) - Based on, now internalized
- **membrane_h26x_plugin** - H.264/H.265 parser
- **membrane_rtp_h264_plugin** - RTP payloader for H.264
- **membrane_fake_plugin** - Testing sink

### Original Plugin
- Repository: https://github.com/membraneframework/membrane_rpicam_plugin
- License: Apache 2.0
- Version: Based on v0.1.5 with fixes

---

**Phase 1 Complete!** 🎉
