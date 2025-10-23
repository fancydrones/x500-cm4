# Video Streamer Hardware Testing Guide

## Prerequisites

### Raspberry Pi Setup
- Raspberry Pi 5 (or CM5) with camera connected
- SSH access enabled
- Network connectivity
- Elixir 1.18+ and Erlang/OTP 27+ installed

### Local Machine Setup
- VLC or ffplay installed for viewing streams
- SSH client
- Network access to Raspberry Pi

## Phase 1.7: Hardware Testing via SSH

### Test 1: Verify Camera Detection

```bash
# SSH into the Pi
ssh user@pi-ip-address

# List available cameras
libcamera-hello --list-cameras

# Expected output:
# Available cameras
# -----------------
# 0 : imx708 [4608x2592] (/base/soc/i2c0mux/i2c@1/imx708@1a)
```

**Pass Criteria:** Camera is detected and listed

---

### Test 2: Verify libcamera-vid H.264 Encoding

```bash
# Capture 10 seconds of H.264 video
libcamera-vid -t 10000 --codec h264 -o /tmp/test.h264

# Check file was created
ls -lh /tmp/test.h264

# Expected: File size should be several MB
```

**Pass Criteria:** Video file created successfully, no errors

---

### Test 3: Check GPU Memory Allocation

```bash
# Check current GPU memory
vcgencmd get_mem gpu

# Should show at least 128MB
# If not, edit /boot/firmware/config.txt and add:
# gpu_mem=256
```

**Pass Criteria:** GPU memory ≥ 128MB

---

### Test 4: Install and Compile Video Streamer

```bash
# Navigate to project
cd /path/to/x500-cm4/apps/video_streamer

# Get dependencies (if not already done)
mix deps.get

# Compile
mix compile

# Expected: Compiles without errors
```

**Pass Criteria:** Application compiles successfully

---

### Test 5: Run Basic Pipeline

```bash
# Start the application in development mode
MIX_ENV=dev iex -S mix

# You should see in the logs:
# [info] Starting VideoStreamer application
# [info] Pipeline manager starting
# [info] Auto-starting streaming pipeline
# [info] Pipeline started successfully

# Check pipeline status
iex> VideoStreamer.PipelineManager.get_status()

# Expected output:
# %{status: :running, config: %{camera: [...], rtsp: [...], encoder: [...]}}
```

**Pass Criteria:**
- Application starts without crashing
- Pipeline manager reports :running status
- No error messages about camera access

---

### Test 6: Verify Pipeline Output (Phase 2 Required)

**Note:** This test requires Phase 2 (RTSP Server) to be implemented first.

Once Phase 2 is complete:

```bash
# On Raspberry Pi - ensure application is running
MIX_ENV=dev iex -S mix

# On your local machine - connect with VLC
vlc rtsp://pi-ip-address:8554/video

# Or use ffplay for lower latency
ffplay -fflags nobuffer -flags low_delay rtsp://pi-ip-address:8554/video
```

**Pass Criteria:**
- Video stream visible in VLC/ffplay
- No major artifacts or corruption
- Stream is relatively smooth

---

### Test 7: Measure CPU and Memory Usage

```bash
# In another SSH session while app is running
ssh user@pi-ip-address

# Monitor resources
htop

# Or more detailed:
top -p $(pgrep -f beam.smp)

# Check memory usage
ps aux | grep beam
```

**Expected Performance:**
- CPU: 5-15% when idle, 20-40% when streaming
- Memory: 100-200MB
- System should remain responsive

**Pass Criteria:**
- CPU usage within acceptable range
- Memory usage < 500MB
- No memory leaks over 5+ minutes

---

### Test 8: Pipeline Restart Test

```bash
# In the IEx session
iex> VideoStreamer.PipelineManager.stop_streaming()
# Expected: {:ok, :stopped}

iex> VideoStreamer.PipelineManager.get_status()
# Expected: %{status: :stopped, ...}

iex> VideoStreamer.PipelineManager.start_streaming()
# Expected: {:ok, :started}

iex> VideoStreamer.PipelineManager.get_status()
# Expected: %{status: :running, ...}
```

**Pass Criteria:**
- Pipeline stops cleanly
- Pipeline restarts successfully
- No error messages or crashes

---

### Test 9: Configuration Change Test

```bash
# In the IEx session, restart with new config
iex> new_config = %{
...>   camera: [width: 1280, height: 720, framerate: 30],
...>   rtsp: Application.get_env(:video_streamer, :rtsp),
...>   encoder: Application.get_env(:video_streamer, :encoder)
...> }

iex> VideoStreamer.PipelineManager.restart_streaming(new_config)
# Expected: {:ok, :restarted}

iex> VideoStreamer.PipelineManager.get_status()
# Check that config shows new resolution
```

**Pass Criteria:**
- Configuration updates accepted
- Pipeline restarts with new settings
- New settings reflected in status

---

### Test 10: Long-Running Stability Test

```bash
# Start the application
MIX_ENV=dev iex -S mix

# Let it run for 30+ minutes
# Monitor logs for any errors or warnings
# Check memory usage periodically
```

**Pass Criteria:**
- Application runs without crashes
- No memory leaks (memory should stabilize)
- No repeated error messages
- CPU usage remains stable

---

## Troubleshooting Common Issues

### Camera Not Detected

```bash
# Check if camera is enabled in config
sudo raspi-config
# Navigate to: Interface Options > Camera > Enable

# Or edit directly
sudo nano /boot/firmware/config.txt
# Ensure: camera_auto_detect=1

# Reboot
sudo reboot
```

### Permission Denied Errors

```bash
# Add user to video group
sudo usermod -a -G video $USER

# Re-login for changes to take effect
exit
ssh user@pi-ip-address
```

### libcamera-vid Not Found

```bash
# Install libcamera tools
sudo apt update
sudo apt install -y libcamera-apps libcamera-tools
```

### Compilation Errors

```bash
# Install build dependencies
sudo apt install -y build-essential git

# Clean and recompile
mix deps.clean --all
mix deps.get
mix compile
```

### Out of Memory

```bash
# Check available memory
free -h

# Increase swap if needed
sudo dphys-swapfile swapoff
sudo nano /etc/dphys-swapfile
# Set: CONF_SWAPSIZE=2048
sudo dphys-swapfile setup
sudo dphys-swapfile swapon
```

---

## Performance Benchmarks

After successful testing, record these metrics:

| Metric | Target | Actual | Notes |
|--------|--------|--------|-------|
| Startup Time | < 5s | ___s | Time from app start to pipeline running |
| CPU Usage (Idle) | < 10% | ___% | While pipeline running, no clients |
| CPU Usage (Streaming) | < 30% | ___% | With 1 active RTSP client (Phase 2+) |
| Memory Usage | < 200MB | ___MB | Stable after 10 minutes |
| Camera Init Time | < 2s | ___s | Time for camera to start capturing |

---

## Test Results Template

```
Date: __________
Tester: __________
Hardware: Raspberry Pi 5 / CM5
Camera: __________
Elixir Version: __________
Erlang Version: __________

Test 1 (Camera Detection): [ ] PASS [ ] FAIL
Test 2 (H.264 Encoding): [ ] PASS [ ] FAIL
Test 3 (GPU Memory): [ ] PASS [ ] FAIL
Test 4 (Compilation): [ ] PASS [ ] FAIL
Test 5 (Basic Pipeline): [ ] PASS [ ] FAIL
Test 6 (Pipeline Output): [ ] PASS [ ] FAIL [ ] SKIPPED (Phase 2 pending)
Test 7 (Performance): [ ] PASS [ ] FAIL
Test 8 (Restart): [ ] PASS [ ] FAIL
Test 9 (Config Change): [ ] PASS [ ] FAIL
Test 10 (Stability): [ ] PASS [ ] FAIL

Notes:
_______________________________________
_______________________________________
_______________________________________

Overall Result: [ ] PASS [ ] FAIL
```

---

## Next Steps After Testing

Once all tests pass:
- [ ] Update implementation checklist with test results
- [ ] Document any configuration tweaks needed
- [ ] Record performance benchmarks
- [ ] Move to Phase 2 (RTSP Server Implementation)
