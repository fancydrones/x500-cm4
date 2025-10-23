# Deployment Verification Checklist

## 1. Verify Code is Updated

```bash
cd /path/to/x500-cm4
git log --oneline -5
```

Should show:
```
b4c810d docs: Update with Baseline Profile fix for iOS VLC
0824065 fix: Switch to H.264 Baseline Profile for iOS/mobile compatibility
69f6de8 feat: Enhance SDP with additional attributes for mobile client compatibility
...
```

## 2. Verify Source Code Has Fix

```bash
cd apps/video_streamer
grep "profile baseline" lib/membrane_rpicam/source.ex
```

Should show:
```elixir
"#{app_binary} -t #{timeout} --codec h264 --profile baseline --libav-format h264 ...
```

## 3. Verify SDP Code Has Fix

```bash
grep "42E01F" lib/video_streamer/rtsp/sdp.ex
```

Should show:
```elixir
profile_level_id = Map.get(codec_params, :profile_level_id, "42E01F")
```

## 4. Recompile (If Not Done)

```bash
mix deps.get
mix compile
```

Should show:
```
Compiling 2 files (.ex)
Generated video_streamer app
```

## 5. Restart Service

**If running as systemd service:**
```bash
sudo systemctl restart video_streamer
sudo systemctl status video_streamer
```

**If running manually:**
```bash
# Kill old process
pkill -f video_streamer

# Start new one
cd apps/video_streamer
iex -S mix
```

## 6. Check Logs for Camera Command

```bash
# For systemd:
journalctl -u video_streamer -f

# For manual:
# Watch the console output
```

Look for a line showing the rpicam-vid command. Should include `--profile baseline`:
```
rpicam-vid -t 0 --codec h264 --profile baseline --libav-format h264 --framerate 30.0 --width 1920 --height 1080 --nopreview -o -
```

## 7. Test SDP Retrieval

Use VLC to connect, then check logs for DESCRIBE request:
```bash
journalctl -u video_streamer -n 100 | grep -A 5 "DESCRIBE"
```

Should show SDP generation.

## 8. Get SDP Using ffprobe

```bash
ffprobe -rtsp_transport tcp rtsp://10.5.0.26:8554/video 2>&1 | grep -i profile
```

Should mention profile information.

## 9. Test with iOS VLC

1. Open VLC on iPad
2. Network Stream → `rtsp://10.5.0.26:8554/video`
3. Should now play video!

## Common Issues

### Issue: iOS Still Shows Audio Only

**Cause**: Old code still running

**Fix**:
1. Verify steps 1-3 above (code is updated)
2. Make absolutely sure service restarted (step 5)
3. Check logs show new command (step 6)

### Issue: grep Commands Show Nothing

**Cause**: You're in the wrong directory

**Fix**:
```bash
cd /path/to/x500-cm4/apps/video_streamer
pwd  # Should end with /apps/video_streamer
```

### Issue: Can't See rpicam-vid Command in Logs

**Cause**: Logging level might not show it

**Fix**: Watch the process:
```bash
ps aux | grep rpicam
```

Should show:
```
rpicam-vid -t 0 --codec h264 --profile baseline ...
```

## Quick Test

If everything is deployed correctly, this should work:

```bash
# On Raspberry Pi
ps aux | grep rpicam | grep baseline
```

Should show a process with `--profile baseline` in the command.

If it doesn't show `--profile baseline`, the fix is NOT deployed!
