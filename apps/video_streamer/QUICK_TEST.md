# Quick Multi-Client Test Reference

## Quick Deploy
```bash
cd /Users/royveshovda/src/fancydrones/x500-cm4

# Commit changes
git add apps/video_streamer/lib/video_streamer/*.ex
git add apps/video_streamer/lib/video_streamer/rtsp/*.ex
git commit -m "feat: Phase 3 multi-client support with Tee"

# Push to repo (if using remote deployment)
git push

# On Raspberry Pi:
# - Pull latest code
# - Restart video_streamer service or run: iex -S mix
```

## Quick Test Commands

### Connect Client 1 (VLC)
```bash
vlc rtsp://<raspberry-pi-ip>:8554/video
```

### Connect Client 2 (ffplay)
```bash
ffplay -rtsp_transport tcp rtsp://<raspberry-pi-ip>:8554/video
```

### Connect Client 3 (GStreamer)
```bash
gst-launch-1.0 rtspsrc location=rtsp://<raspberry-pi-ip>:8554/video ! \
  rtph264depay ! h264parse ! avdec_h264 ! autovideosink
```

## Quick Monitoring

### Watch Active Clients in Logs
```bash
# Look for these patterns:
journalctl -u video_streamer -f | grep "Active clients"
```

### Check RTP Connections
```bash
# Should show one connection per active client
netstat -an | grep :50000 | wc -l
```

### Monitor Performance
```bash
# Quick CPU/Memory check
htop
```

## What to Look For

### ✅ Success Indicators
- Multiple clients playing video simultaneously
- Log shows: `Active clients: 2` (or more)
- Each client has different SSRC in logs
- Disconnecting one client doesn't affect others
- No "Restarting pipeline" messages

### ❌ Problem Indicators
- Pipeline restarts on new client connect
- Only one client can connect at a time
- Clients drop when another connects
- Memory usage growing continuously
- Errors about missing children

## Essential Tests (5 minutes)

1. **Connect Client 1** → Verify video plays
2. **Connect Client 2** → Verify both play
3. **Disconnect Client 1** → Verify Client 2 continues
4. **Connect Client 3** → Verify 2 & 3 play
5. **Disconnect all** → Verify clean shutdown

If all 5 work: **Phase 3 Success! ✅**

## Key Log Messages

**Good:**
```
[info] Adding client abc123: 192.168.1.100:5000
[info] Client abc123 added with SSRC 123456. Active clients: 2
```

**Bad (shouldn't see):**
```
[info] Restarting pipeline with config...  ❌ (Phase 2 behavior)
```

## Emergency Rollback

If Phase 3 causes issues, revert to Phase 2:
```bash
git revert HEAD
# Redeploy
```

---
See [PHASE3_TESTING.md](./PHASE3_TESTING.md) for comprehensive testing guide.
