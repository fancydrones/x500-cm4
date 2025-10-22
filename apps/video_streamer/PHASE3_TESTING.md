# Phase 3 Multi-Client Testing Guide

## Overview
Phase 3 implements multi-client support using Membrane.Tee, allowing multiple viewers to watch the video stream simultaneously without pipeline restarts.

## Changes in Phase 3

### Architecture
- **Before (Phase 2)**: Single client, pipeline restart on each PLAY
- **After (Phase 3)**: Multiple clients, dynamic client add/remove via Tee

### Modified Files
1. `lib/video_streamer/pipeline.ex` - Uses Tee.Master for multi-output
2. `lib/video_streamer/pipeline_manager.ex` - Added add_client/remove_client APIs
3. `lib/video_streamer/rtsp/session.ex` - PLAY adds client, TEARDOWN removes client

## Pre-Deployment Checklist

- [x] Code compiles successfully
- [x] All dependencies resolved
- [ ] Code committed to git
- [ ] Deployed to Raspberry Pi
- [ ] Camera hardware connected
- [ ] Network connectivity verified

## Deployment Steps

### 1. Commit Changes
```bash
cd /Users/royveshovda/src/fancydrones/x500-cm4
git add apps/video_streamer/lib/video_streamer/pipeline.ex
git add apps/video_streamer/lib/video_streamer/pipeline_manager.ex
git add apps/video_streamer/lib/video_streamer/rtsp/session.ex
git commit -m "feat: Implement Phase 3 multi-client support with Membrane.Tee

- Refactor pipeline to use Tee.Master for stream splitting
- Add dynamic client add/remove handlers
- Update PipelineManager with add_client/remove_client APIs
- Update RTSP session to use client management instead of pipeline restart
- Each client gets unique SSRC for RTP identification
- Automatic client cleanup on disconnect

Phase 3 implementation complete, ready for hardware testing."
```

### 2. Deploy to Raspberry Pi
Follow your standard deployment process (e.g., git pull, mix deps.get, restart service)

## Testing Procedure

### Test 1: Single Client (Regression Test)
**Purpose**: Verify Phase 2 functionality still works

1. Start the video_streamer application on Raspberry Pi
2. Check logs for pipeline startup: `Pipeline init - multi-client mode with Tee`
3. Connect one VLC client: `vlc rtsp://<pi-ip>:8554/video`
4. **Expected**:
   - Log shows "Adding client <session-id>"
   - Log shows "Active clients: 1"
   - Video plays smoothly
5. Disconnect VLC
6. **Expected**:
   - Log shows "Removing client <session-id>"
   - Log shows "Active clients: 0"
   - No pipeline crash

**Pass Criteria**: ✅ Single client works as before

---

### Test 2: Two Simultaneous Clients
**Purpose**: Verify basic multi-client functionality

1. Ensure video_streamer is running
2. Connect Client 1 (VLC): `vlc rtsp://<pi-ip>:8554/video`
3. Wait for video to start playing
4. Connect Client 2 (VLC): `vlc rtsp://<pi-ip>:8554/video`
5. **Expected**:
   - Log shows "Adding client" twice
   - Log shows "Active clients: 2"
   - Both clients display video simultaneously
   - Both streams are smooth
   - Each client has different SSRC in logs

6. Disconnect Client 1
7. **Expected**:
   - Client 2 continues playing without interruption
   - Log shows "Active clients: 1"

8. Disconnect Client 2
9. **Expected**:
   - Log shows "Active clients: 0"
   - Pipeline still running

**Pass Criteria**: ✅ Two clients can view simultaneously

---

### Test 3: Three or More Clients
**Purpose**: Test scalability

1. Connect 3-5 clients simultaneously:
   - Client 1: VLC on laptop
   - Client 2: VLC on phone/tablet
   - Client 3: QGroundControl (if available)
   - Client 4+: Additional VLC instances

2. **Expected**:
   - All clients show video
   - Log shows correct active client count
   - Video quality acceptable on all clients
   - No significant lag or frame drops

3. **Monitor**:
   - CPU usage: `top` or `htop` on Raspberry Pi
   - Memory usage
   - Network bandwidth

**Pass Criteria**: ✅ 3+ clients work acceptably (may have performance degradation)

---

### Test 4: Rapid Connect/Disconnect
**Purpose**: Test robustness of client management

1. Quickly connect and disconnect clients (within 1-2 seconds)
2. Repeat 5-10 times
3. **Expected**:
   - No crashes
   - Client count remains accurate
   - No zombie client branches in pipeline
   - Memory doesn't leak

4. Check final state:
   - All clients disconnected
   - Active clients: 0
   - Pipeline still healthy

**Pass Criteria**: ✅ No crashes, leaks, or stuck clients

---

### Test 5: Connect During Active Streaming
**Purpose**: Verify dynamic client addition works smoothly

1. Start with 1 client streaming for 30+ seconds
2. Add Client 2 while Client 1 is playing
3. **Expected**:
   - Client 2 connects and plays immediately
   - Client 1 is not interrupted
   - Both receive same video frames (check timestamps)

**Pass Criteria**: ✅ New clients can join without disruption

---

### Test 6: Different RTSP Clients
**Purpose**: Test compatibility with various clients

Test with:
- [ ] VLC (desktop)
- [ ] VLC (mobile)
- [ ] QGroundControl
- [ ] ffplay: `ffplay rtsp://<pi-ip>:8554/video`
- [ ] GStreamer:
  ```bash
  gst-launch-1.0 rtspsrc location=rtsp://<pi-ip>:8554/video ! \
    rtph264depay ! h264parse ! avdec_h264 ! autovideosink
  ```

**Pass Criteria**: ✅ All tested clients work

---

### Test 7: Long Duration Multi-Client
**Purpose**: Check for memory leaks and stability

1. Connect 2 clients
2. Let them run for 10+ minutes
3. **Monitor**:
   - Memory usage over time
   - CPU usage stability
   - Any log errors or warnings
   - Video quality remains consistent

**Pass Criteria**: ✅ Stable for 10+ minutes, no memory growth

---

### Test 8: Network Stress Test
**Purpose**: Test behavior under poor network conditions

1. Connect clients over WiFi (not Ethernet)
2. Move around to vary signal strength
3. **Expected**:
   - Clients may buffer/stutter but shouldn't crash
   - Reconnecting client works
   - Other clients not affected

**Pass Criteria**: ✅ Graceful degradation, no crashes

---

## Monitoring Commands

### On Raspberry Pi:

**Watch logs in real-time:**
```bash
# If running via mix
iex -S mix

# If running as service
journalctl -u video_streamer -f
```

**Check CPU/Memory:**
```bash
htop
# or
top
```

**Check network bandwidth:**
```bash
iftop
# or
nload
```

**Count active RTP streams:**
```bash
netstat -an | grep :50000
# Should show one line per active client
```

## Expected Log Messages

### Client Connect (PLAY):
```
[info] PLAY: Adding client <session-id> to pipeline: <ip>:<port>
[info] Adding client <session-id>: <ip>:<port>
[info] Client <session-id> added with SSRC <number>. Active clients: N
[info] Client <ip> started playing (session: <session-id>)
```

### Client Disconnect (TEARDOWN):
```
[info] TEARDOWN: Removing client <session-id> from pipeline
[info] Removing client <session-id>
[info] Client <session-id> removed. Active clients: N
[info] Client <ip> teardown completed (session: <session-id>)
```

### Client Disconnect (TCP Close):
```
[info] Client <ip> disconnected
[info] Removing disconnected client <session-id> from pipeline
[info] Removing client <session-id>
[info] Client <session-id> removed. Active clients: N
```

## Troubleshooting

### Issue: Client connects but no video
**Check:**
- Does log show "Adding client"?
- Is SSRC unique for each client?
- Try single client first (regression test)

### Issue: Second client causes first to disconnect
**Check:**
- Old Phase 2 code still running?
- Pipeline restarting instead of adding client?
- Look for "Restarting pipeline" in logs (shouldn't appear)

### Issue: Client disconnect doesn't clean up
**Check:**
- `netstat` for lingering UDP connections
- Log shows "Removing client"?
- Memory usage increasing?

### Issue: Pipeline crashes on client disconnect
**Check:**
- Full error stack trace
- Which child terminated?
- Tee properly managing branches?

## Success Criteria Summary

Phase 3 is successful if:

- ✅ At least 2 clients can stream simultaneously
- ✅ Clients can connect/disconnect without affecting others
- ✅ No pipeline restarts during client operations
- ✅ Clean client removal on disconnect
- ✅ Unique SSRC per client
- ✅ Stable for 10+ minutes
- ✅ Compatible with VLC and QGroundControl

## Performance Targets

- **2 clients**: Smooth, <200ms latency
- **3-5 clients**: Acceptable, <500ms latency
- **CPU usage**: <80% with 3 clients
- **Memory**: Stable (no growth over time)

## Reporting Results

After testing, update `PRDs/002-video-streamer/implementation_checklist.md`:

1. Mark Test 3.2 item as complete: "Test adding/removing clients dynamically"
2. Mark Test 3.3 item as complete: "Test end-to-end flow (RTSP → RTP → multi-client)"
3. Fill in Test 3.5 results
4. Update Phase 3 Notes with findings
5. Update completion criteria with actual results

## Notes

- Each client gets its own StreamSendBin with unique SSRC
- The Tee.Master element splits H.264 stream to all clients
- No shared state between clients except the camera source
- Session ID is used as client_id for tracking
- UDP port 50000 is used for all RTP sending (source port)

---

**Good luck with testing! 🚀**
