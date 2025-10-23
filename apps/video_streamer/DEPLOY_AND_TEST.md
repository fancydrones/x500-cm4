# Deploy and Test iOS VLC Fix

## Quick Deployment Steps

### 1. Deploy to Raspberry Pi
```bash
# On Raspberry Pi, pull latest changes
cd /path/to/x500-cm4
git pull
cd apps/video_streamer
mix deps.get
mix compile

# Restart the service
sudo systemctl restart video_streamer
# OR if running manually:
# pkill -f video_streamer
# iex -S mix
```

### 2. Verify Server is Running
```bash
# Check process
ps aux | grep video_streamer

# Check logs
journalctl -u video_streamer -f
# OR
tail -f /var/log/video_streamer.log
```

### 3. Verify SDP Contains Real SPS/PPS
From your Mac:
```bash
echo "DESCRIBE rtsp://10.5.0.26:8554/video RTSP/1.0
CSeq: 1
Accept: application/sdp

" | nc 10.5.0.26 8554 | grep "a=fmtp"
```

**Expected output:**
```
a=fmtp:96 packetization-mode=1;profile-level-id=42C01F;sprop-parameter-sets=Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=,aM4PyA==
```

**Key things to verify:**
- `profile-level-id=42C01F` (not 42E01F)
- `sprop-parameter-sets=Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=,aM4PyA==` (26-char SPS, not 14-char generic one)

## iOS VLC Test

### Quick Test (30 seconds)
1. Open VLC on iPad
2. Network Stream → `rtsp://10.5.0.26:8554/video`
3. **Expected**: Video displays (not just audio)

### Detailed Test (2 minutes)
1. Connect iOS VLC
2. Check video is smooth
3. Verify no artifacts or corruption
4. Disconnect and reconnect - should work both times
5. While iOS is playing, connect macOS VLC - both should work

## Troubleshooting

### If iOS Still Shows Audio-Only

**Check 1: Is the new code deployed?**
```bash
# On Raspberry Pi
cd apps/video_streamer
git log -1 --oneline
# Should show: 97bf670 fix: Use real camera SPS/PPS in SDP for iOS VLC compatibility
```

**Check 2: Is the service restarted?**
```bash
# Check when process started
ps aux | grep video_streamer
```

**Check 3: Is SDP updated?**
```bash
# From Mac, check SDP
echo "DESCRIBE rtsp://10.5.0.26:8554/video RTSP/1.0
CSeq: 1
Accept: application/sdp

" | nc 10.5.0.26 8554 | grep -A 30 "v=0"
```

Look for the long SPS: `Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=` (not the short generic one)

**Check 4: Test with ffprobe**
```bash
ffprobe -rtsp_transport udp rtsp://10.5.0.26:8554/video 2>&1 | grep -i "non-existing"
```
Should see NO errors about "non-existing PPS"

### If macOS VLC Stops Working

This shouldn't happen, but if it does:
1. The real SPS/PPS should work for everyone
2. Try UDP transport: `rtsp://10.5.0.26:8554/video?transport=udp`
3. Check server logs for errors

## Success Criteria

- ✅ macOS VLC: Video plays smoothly (regression test)
- ✅ iOS VLC: Video plays (NOT just audio)
- ✅ Multiple clients: 2+ clients work simultaneously
- ✅ Reconnect: Disconnect and reconnect works on iOS
- ✅ No errors: ffprobe shows no PPS/SPS errors

## If All Tests Pass

Update the implementation checklist:
```bash
vim PRDs/002-video-streamer/implementation_checklist.md
```

Mark these as complete:
- ✅ Test 3.2: Multi-client testing (Phase 3)
- ✅ Test 3.3: iOS VLC compatibility
- ✅ Test 3.5: QGroundControl compatibility (if tested)

Then document in checklist:
- Number of simultaneous clients tested
- Devices tested (macOS VLC, iOS VLC, QGroundControl)
- Any performance notes (latency, CPU usage)

## Next Phase

Once iOS VLC works reliably:
1. Performance testing (CPU/memory with 3+ clients)
2. Long-duration stability test (10+ minutes)
3. QGroundControl compatibility test
4. Mark Phase 3 as COMPLETE

---
**Estimated time to deploy and verify: 5 minutes**
