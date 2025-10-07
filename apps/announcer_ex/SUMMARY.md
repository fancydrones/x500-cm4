# Announcer-Ex Bug Fixes - Summary

## Overview

Fixed **5 critical bugs** preventing the announcer-ex application from properly announcing the camera via MAVLink in the Kubernetes environment.

## Bugs Fixed

### 1. Incorrect Command ACK Routing ✅
- **Symptom**: Command acknowledgements sent to wrong destination
- **Impact**: Camera commands never properly acknowledged
- **Fix**: Extract source system/component from MAVLink frame header
- **Files**: `camera_manager.ex`, `command_handler.ex`

### 2. Wrong XMAVLink Configuration Keys ✅
- **Symptom**: XMAVLink using wrong system/component IDs (245.250 instead of 1.100)
- **Impact**: Camera identified with wrong MAVLink address
- **Fix**: Use `:system_id` and `:component_id` config keys instead of `:system` and `:component`
- **Files**: `config/runtime.exs`

### 3. Runtime Configuration Not Loading ✅
- **Symptom**: Configuration not applied in production releases
- **Impact**: Environment variables ignored
- **Fix**: Remove `if config_env() == :prod` from runtime.exs
- **Files**: `config/runtime.exs`

### 4. Insufficient Logging ✅
- **Symptom**: Hard to debug issues
- **Impact**: Difficult troubleshooting
- **Fix**: Added debug logging and XMAVLink config output
- **Files**: `config/prod.exs`, `application.ex`

### 5. XMAVLink UDP Socket Binding Bug ✅ (CRITICAL)
- **Symptom**: `:eaddrnotavail` error when connecting to router
- **Impact**: Complete failure to establish MAVLink connection
- **Fix**: Patched `XMAVLink.UDPOutConnection` to remove incorrect IP binding
- **Files**: `lib/announcer_ex/udp_out_connection_patch.ex` (new)

## Test Results

```
✓ All tests passing
✓ Correct system_id (1) and component_id (100)
✓ UDP connection successfully opened
✓ Heartbeats being sent
✓ Camera manager initialized
```

## Next Steps

1. **Build new Docker image** with all fixes
2. **Deploy to Kubernetes** and verify:
   - No `:eaddrnotavail` errors
   - Camera appears in ground station
   - Camera commands properly acknowledged
   - Video stream information available

## Files Changed

- `lib/announcer_ex/application.ex` - Added XMAVLink config logging
- `lib/announcer_ex/camera_manager.ex` - Pass full frame to command handler
- `lib/announcer_ex/command_handler.ex` - Extract source from frame header for ACKs
- `config/runtime.exs` - Fixed XMAVLink config keys and removed conditional
- `config/prod.exs` - Set log level to debug
- `lib/announcer_ex/udp_out_connection_patch.ex` - **NEW**: Patched UDP connection module

## Documentation

- `FIXES.md` - Detailed explanation of all issues and fixes
- `UDP_FIX.md` - Detailed explanation of the XMAVLink UDP socket bug and patch

## Build Command

```bash
cd apps/announcer_ex
docker build -t ghcr.io/fancydrones/x500-cm4/announcer-ex:latest .
docker push ghcr.io/fancydrones/x500-cm4/announcer-ex:latest
```

## Verification Commands

```bash
# Check pod status
kubectl get pods -n rpiuav | grep announcer-ex

# View logs
kubectl logs -n rpiuav -l app=announcer-ex-replicaset --tail=100

# Look for success indicators:
# - "Opened udpout:..." (not "Could not open...")
# - "Camera initialized: Front (ID: 100) on system 1"
# - "XMAVLink configuration: [... system_id: 1, component_id: 100]"
# - No ":eaddrnotavail" errors
```

## Production Recommendations

1. **Monitor for a few hours** after deployment
2. **Test camera functionality** from ground station (QGroundControl)
3. **Reduce log level** to `:info` once stable (edit `config/prod.exs`)
4. **Report XMAVLink bug** upstream or fork the library

All bugs have been identified and fixed. The application is ready for deployment.
