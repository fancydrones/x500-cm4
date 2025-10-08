# 🎯 ROOT CAUSE FOUND AND FIXED!

## The Problem

CAMERA_INFORMATION (message 259) was being broadcast by the camera but **never reached QGC**. VIDEO_STREAM_INFORMATION (269) and VIDEO_STREAM_STATUS (270) worked fine.

## Root Cause

**The `vendor_name` and `model_name` fields were using the wrong data type!**

### What Was Wrong

```elixir
# INCORRECT - Binary string
vendor_name: pad_bytes(state.camera_name, 32)  # Returns BitString
model_name: pad_bytes(state.camera_name, 32)   # Returns BitString
```

The MAVLink specification defines these fields as:
```
vendor_name: [ XMAVLink.Types.uint8_t ]  # List of integers!
model_name: [ XMAVLink.Types.uint8_t ]   # List of integers!
```

When trying to pack the message, xmavlink's `pack_array` function expected a **List** but got a **BitString**, causing the pack operation to fail silently. The message was never actually sent!

### The Fix

```elixir
# CORRECT - List of byte values
vendor_bytes = String.to_charlist(vendor) |> Enum.concat(List.duplicate(0, 32)) |> Enum.take(32)
model_bytes = String.to_charlist(model) |> Enum.concat(List.duplicate(0, 32)) |> Enum.take(32)

vendor_name: vendor_bytes  # List of integers
model_name: model_bytes    # List of integers
```

## Files Changed

**[message_builder.ex](lib/announcer_ex/message_builder.ex#L23-L48)** - Fixed vendor_name and model_name encoding

## Why VIDEO_STREAM_INFORMATION Worked

VIDEO_STREAM_INFORMATION uses `name` and `uri` fields which are defined as `[ char ]` (character arrays) and xmavlink's `pack_string` function handles binary strings correctly. But CAMERA_INFORMATION uses byte arrays that require lists.

## Test Results

Before fix:
```
** (Protocol.UndefinedError) protocol Enumerable not implemented for type BitString
```

After fix:
```
Pack result: {:ok, 259, {:ok, 92, 235, :broadcast}, <<...>>}  ✅
```

## Next Steps

1. **Deploy the updated code** to the cluster
2. **Check QGC MAVLink Inspector** - You should now see message 259 (CAMERA_INFORMATION) appearing every 5 seconds
3. **Camera should appear in QGC** automatically!

## Deployment

```bash
# Build and deploy
cd /Users/royveshovda/src/fancydrones/x500-cm4
make announcer-ex-build
make announcer-ex-push

# Update image tag in deployment yaml
kubectl apply -f deployments/apps/announcer-ex-deployment.yaml
```

## Verification

After deployment:

```bash
# Check logs
kubectl logs -n rpiuav <announcer-pod> -f | grep "Broadcast CAMERA"
```

In QGC MAVLink Inspector, you should see:
- Message 0 (HEARTBEAT) ✅
- Message 259 (CAMERA_INFORMATION) ✅ **NEW!**
- Message 269 (VIDEO_STREAM_INFORMATION) ✅
- Message 270 (VIDEO_STREAM_STATUS) ✅

Then the camera should appear in QGC and video should start automatically!

## Summary of All Fixes

Throughout this debugging session, we fixed:

1. ✅ **Broadcast command handling** - Camera now responds to target_component=0
2. ✅ **Router message filters** - Added 75,259,269,270 to AllowMsgIdOut
3. ✅ **Heartbeat autopilot field** - Changed to :mav_autopilot_invalid
4. ✅ **Periodic camera info broadcast** - QGC 5.0.7 compatibility
5. ✅ **CAMERA_INFORMATION encoding** - Fixed vendor_name/model_name to use lists ← **THE CRITICAL FIX**

This final fix (#5) was the root cause preventing CAMERA_INFORMATION from being sent.
