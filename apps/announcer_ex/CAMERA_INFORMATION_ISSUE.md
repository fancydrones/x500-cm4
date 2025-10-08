# CAMERA_INFORMATION Not Reaching QGC - Deep Dive

## Symptoms

In QGC MAVLink Inspector, from System 1 Component 100:
- ✅ Message 0 (HEARTBEAT) - appears
- ❌ Message 259 (CAMERA_INFORMATION) - does NOT appear
- ✅ Message 269 (VIDEO_STREAM_INFORMATION) - appears
- ✅ Message 270 (VIDEO_STREAM_STATUS) - appears

## What We've Ruled Out

1. ✅ Router filters - All endpoints now allow message 259
2. ✅ Code compilation - No errors in building CAMERA_INFORMATION
3. ✅ Logs show - "Broadcast CAMERA_INFORMATION and VIDEO_STREAM_INFORMATION"
4. ✅ System/Component IDs - Correct (1/100)

## Most Likely Causes

### Cause 1: CAMERA_INFORMATION Fails to Serialize (90% likely)

The `Router.pack_and_send(camera_info)` call might be failing silently.

**Why VIDEO_STREAM_INFORMATION works but CAMERA_INFORMATION doesn't:**
- Different message structures
- CAMERA_INFORMATION has more complex fields (vendor_name, model_name as byte arrays)
- CAMERA_INFORMATION might have an invalid field value

**Test:** Deploy code with enhanced logging (already added in camera_manager.ex) to see `pack_and_send` results.

### Cause 2: CAMERA_INFORMATION Packet is Malformed (50% likely)

The message serializes but creates an invalid MAVLink packet that:
- Router drops silently
- Or QGC rejects/ignores

**Common issues:**
- String fields with invalid characters
- Null bytes in wrong positions
- Field length mismatches

### Cause 3: Message Ordering Issue (10% likely)

CAMERA_INFORMATION and VIDEO_STREAM_INFORMATION are sent in quick succession. Maybe:
- First message (CAMERA_INFORMATION) gets dropped due to timing
- Buffer overflow
- UDP packet loss

## Recommended Debugging Steps

### Step 1: Deploy Enhanced Logging

The code already has this change in camera_manager.ex (line 93-107):
```elixir
Logger.debug("Sending CAMERA_INFORMATION: vendor=...")
result1 = Router.pack_and_send(camera_info)
Logger.debug("CAMERA_INFORMATION pack_and_send result: #{inspect(result1)}")
```

**Deploy this version and check logs for the `pack_and_send result`.**

If it shows an error or `:error`, that's the problem.

### Step 2: Test Messages Separately

Temporarily send ONLY CAMERA_INFORMATION, not VIDEO_STREAM_INFORMATION:

```elixir
def handle_info(:send_camera_info, state) do
  camera_info = MessageBuilder.build_camera_information(state)
  Router.pack_and_send(camera_info)
  # Comment out stream_info temporarily
  # stream_info = MessageBuilder.build_video_stream_information(state)
  # Router.pack_and_send(stream_info)

  schedule_camera_info()
  {:noreply, state}
end
```

If CAMERA_INFORMATION appears in QGC when sent alone, it's a timing/ordering issue.

### Step 3: Simplify CAMERA_INFORMATION

Try with minimal fields:

```elixir
def build_camera_information(state) do
  %Common.Message.CameraInformation{
    time_boot_ms: 0,  # Simplified
    vendor_name: pad_bytes("Test", 32),  # Hardcoded
    model_name: pad_bytes("Camera", 32),  # Hardcoded
    firmware_version: 1,
    focal_length: 0.0,
    sensor_size_h: 0.0,
    sensor_size_v: 0.0,
    resolution_h: 1280,
    resolution_v: 720,
    lens_id: 0,
    flags: MapSet.new([:camera_cap_flags_has_video_stream]),
    cam_definition_version: 1,
    cam_definition_uri: pad_bytes("", 140)
  }
end
```

If this works, gradually add back dynamic fields to find the problematic one.

### Step 4: Check Router Packet Capture

On the router pod, capture packets:

```bash
kubectl exec -n rpiuav <router-pod> -- tcpdump -i any -n udp port 14560 -w - -c 100 | wireshark -k -i -
```

Look for:
- MAVLink packets with message ID 259
- If they exist, they're being sent
- If they're malformed, Wireshark will show decoding errors

### Step 5: Compare Working vs Non-Working Messages

Why does VIDEO_STREAM_INFORMATION work?

```elixir
# This WORKS:
%Common.Message.VideoStreamInformation{
  stream_id: 1,
  count: 1,
  type: :video_stream_type_rtsp,
  flags: :video_stream_status_flags_running,
  framerate: 30.0,
  resolution_h: 1280,
  resolution_v: 720,
  bitrate: 5000,
  rotation: 0,
  hfov: 63,
  name: pad_bytes(state.camera_name, 32),  # Same padding function
  uri: pad_bytes(state.stream_url, 160)
}

# This DOESN'T:
%Common.Message.CameraInformation{
  ...
  vendor_name: pad_bytes(state.camera_name, 32),  # Same padding, same input
  model_name: pad_bytes(state.camera_name, 32),
  ...
}
```

The difference: CAMERA_INFORMATION has MORE fields, complex types (MapSet for flags).

## Quick Workaround

**If you just need the camera to work**, try:

### Option A: Disable CAMERA_INFORMATION Broadcast

Set `ENABLE_CAMERA_INFO_BROADCAST=false` and manually configure video in QGC:
- Settings → Video → RTSP Video Stream
- URL: `rtsp://10.10.10.2:8554/cam`

### Option B: Use Only REQUEST/RESPONSE

Disable periodic broadcast, rely only on QGC requesting info:
```yaml
- name: ENABLE_CAMERA_INFO_BROADCAST
  value: "false"
- name: ENABLE_STREAM_STATUS
  value: "false"
```

Then manually trigger discovery from QGC (if it has that option).

## Next Actions

1. **Deploy code with enhanced logging** (already in camera_manager.ex)
2. **Check logs for `pack_and_send result`**
3. **Report back what the result shows**

If `pack_and_send` returns `:ok` but message still doesn't reach QGC, the packet is malformed.
If `pack_and_send` returns an error, there's a serialization issue.

The logging will tell us exactly what's happening!
