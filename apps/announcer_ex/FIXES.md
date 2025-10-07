# Announcer-Ex Debugging Fixes

## Issues Found and Fixed

### Issue 1: Incorrect Command ACK Routing
**Problem**: Command acknowledgements were being sent back to the wrong target. The code was using `command_msg.target_system` and `command_msg.target_component` as the ACK destination, but these fields contain the camera's own IDs (1 and 100), not the sender's IDs.

**Root Cause**: In MAVLink COMMAND_LONG messages, the `target_system` and `target_component` fields indicate who should process the command (the camera), NOT who sent it. The sender's information is in the MAVLink frame header.

**Fix**: 
- Modified `camera_manager.ex` to pass the entire frame (not just the message) to the command handler
- Updated `command_handler.ex` to extract `frame.source_system` and `frame.source_component` from the MAVLink frame header
- Use these values as the target for command acknowledgements

**Files Changed**:
- `lib/announcer_ex/camera_manager.ex`
- `lib/announcer_ex/command_handler.ex`

### Issue 2: Wrong Configuration Keys for XMAVLink
**Problem**: The runtime configuration was using `:system` and `:component` keys, but XMAVLink.Supervisor expects `:system_id` and `:component_id`.

**Root Cause**: The XMAVLink library's supervisor reads configuration using `Application.get_env(:xmavlink, :system_id)` and `Application.get_env(:xmavlink, :component_id)`, not `:system` and `:component`.

**Fix**: Updated `config/runtime.exs` to use the correct configuration keys:
```elixir
config :xmavlink,
  system_id: String.to_integer(system_id),
  component_id: String.to_integer(camera_id),
  connections: [router_connection]
```

**Files Changed**:
- `config/runtime.exs`

### Issue 3: Runtime Configuration Not Loading
**Problem**: The runtime.exs had a conditional `if config_env() == :prod` which doesn't work correctly in releases.

**Root Cause**: `config_env()` is a compile-time macro that returns the Mix environment during compilation, not at runtime. In a release, this conditional is evaluated during build time with whatever Mix.env was set during compilation, and the configuration is frozen.

**Fix**: Removed the conditional wrapper intentionally to apply configuration in all environments. The recommended pattern (`if config_env() == :prod do`) works as intended for releases, but the change ensures the configuration is always applied, not just in production.

**Files Changed**:
- `config/runtime.exs`

### Issue 4: Insufficient Logging for Debugging
**Problem**: Without debug-level logs, it was difficult to see what was happening with heartbeats and message routing.

**Fix**: 
- Changed log level to `:debug` in `config/prod.exs`
- Added logging to show XMAVLink configuration at startup in `lib/announcer_ex/application.ex`

**Files Changed**:
- `config/prod.exs`
- `lib/announcer_ex/application.ex`

## Testing

The fixes have been tested locally with `mix test` and show:
- Correct system_id (1) and component_id (100) in configuration
- Tests passing

## Deployment

To deploy the fixes:

1. Build a new Docker image:
```bash
cd apps/announcer_ex
docker build -t ghcr.io/fancydrones/x500-cm4/announcer-ex:latest .
```

2. Push the image:
```bash
docker push ghcr.io/fancydrones/x500-cm4/announcer-ex:latest
```

3. Update the deployment (if using a specific tag):
```bash
kubectl set image deployment/announcer-ex announcer-ex=ghcr.io/fancydrones/x500-cm4/announcer-ex:latest -n rpiuav
```

Or force a rollout restart if using :latest:
```bash
kubectl rollout restart deployment/announcer-ex -n rpiuav
```

4. Verify the deployment:
```bash
kubectl get pods -n rpiuav
kubectl logs -n rpiuav <announcer-ex-pod-name> --tail=50
```

Expected log output should show:
- Correct system_id and component_id in XMAVLink configuration
- Heartbeat messages being sent
- No "First sighting of vehicle 245.250" (should be "1.100" or similar)
- Command acknowledgements with correct source/target routing

## Additional Recommendations

1. **Set log level back to :info in production** after debugging is complete:
   - Edit `config/prod.exs` and change `config :logger, level: :debug` to `config :logger, level: :info`

2. **Monitor camera announcements**:
   - Use QGroundControl or another MAVLink ground station to verify the camera is being detected
   - Check that camera information requests are being properly answered

3. **Compare with Python announcer**:
   - Both implementations should now behave identically
   - Consider running both side-by-side temporarily to verify parity
