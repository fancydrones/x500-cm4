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

**Note:** Replace `${VERSION}` with your chosen version string or commit SHA. For example, you can set it with:
```bash
VERSION=$(git rev-parse --short HEAD)
```

Or force a rollout restart if using :latest:
```bash
kubectl rollout restart deployment/announcer-ex -n rpiuav
```

- Verify the deployment:
```bash
kubectl get pods -n rpiuav
kubectl logs -n rpiuav <announcer-ex-pod-name> --tail=50
```

Expected log output should show:
- Correct system_id and component_id in XMAVLink configuration
- Heartbeat messages being sent
- No "First sighting of vehicle 245.250" (should be "1.100" or similar)
- Command acknowledgements with correct source/target routing

### Issue 5: Message Subscription Not Receiving Frames (2025-10-08)
**Problem**: The announcer-ex application was sending heartbeat messages successfully, but was not processing incoming MAVLink COMMAND_LONG messages from the controller (e.g., camera information requests).

**Symptoms**:
- Logs showed: "Received unknown message: %Common.Message.CommandLong{...}"
- Router logs showed: "X messages to unknown endpoints in the last 5 seconds"
- Camera was not being detected by the controller
- Commands like `MAV_CMD_REQUEST_CAMERA_INFORMATION` were received but not processed

**Root Cause**: The `Router.subscribe()` call in `CameraManager.init/1` was using the default `as_frame: false` option, which delivers messages as plain structs. However, the `handle_info/2` function was expecting messages wrapped in a `{:mavlink_message, frame}` tuple format. Additionally, we need the frame format to access `source_system` and `source_component` from the frame header for proper response routing.

When `as_frame: false` (default):
- Messages arrive as: `%Common.Message.CommandLong{...}`

When `as_frame: true`:
- Messages arrive as: `%XMAVLink.Frame{message: %Common.Message.CommandLong{...}, source_system: 1, source_component: 190, ...}`

**Fix**:
1. Updated the subscription to use `as_frame: true`:
   ```elixir
   Router.subscribe(message: Common.Message.CommandLong, as_frame: true)
   ```

2. Updated the `handle_info/2` pattern match to handle the Frame struct directly:
   ```elixir
   def handle_info(frame = %XMAVLink.Frame{message: command_msg}, state)
       when is_struct(command_msg, Common.Message.CommandLong) do
   ```

3. Added logging to show the source of commands for better debugging:
   ```elixir
   Logger.debug(
     "Processing command #{command_msg.command} from #{frame.source_system}/#{frame.source_component} for system #{state.system_id}/#{state.camera_id}"
   )
   ```

**Files Changed**:
- `lib/announcer_ex/camera_manager.ex`

## Additional Recommendations

1. **Set log level back to :info in production** after debugging is complete:
   - Edit `config/prod.exs` and change `config :logger, level: :debug` to `config :logger, level: :info`

2. **Monitor camera announcements**:
   - Use QGroundControl or another MAVLink ground station to verify the camera is being detected
   - Check that camera information requests are being properly answered

3. **Compare with Python announcer**:
   - Both implementations should now behave identically
   - Consider running both side-by-side temporarily to verify parity

````
