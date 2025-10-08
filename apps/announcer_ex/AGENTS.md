# Purpose

This is a MAVLink camera announcer service written in Elixir. The app announces camera capabilities and streaming information to MAVLink-based drone controllers, enabling automatic discovery and configuration of camera systems.

The application:

- Broadcasts camera heartbeat messages via MAVLink protocol
- Responds to camera information and capability requests
- Provides video stream metadata (RTSP URLs, resolution, formats)
- Handles MAVLink camera protocol commands
- Connects to external MAVLink router services via UDP

## Project guidelines

- Use `mix test` to run all tests
- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- The application uses the `:xmavlink` library for MAVLink protocol implementation
- All MAVLink message building and handling is done through `AnnouncerEx.MessageBuilder` and `AnnouncerEx.CommandHandler`
- Camera configuration is managed via environment variables (see `AnnouncerEx.Config`)

## MAVLink Protocol Guidelines

- **Always** use MAVLink 2.0 protocol when `MAVLINK20=1` environment variable is set
- MAVLink component IDs must be unique per camera (configured via `CAMERA_ID` env var)
- System ID identifies the drone/vehicle (configured via `SYSTEM_ID` env var)
- Camera component ID range: 100-199 (MAVLink camera component convention)
- Heartbeat messages **must** be sent every 1 second to maintain presence
- **Always** respond with appropriate MAVLink acknowledgments for commands
- Use `XMAVLink.pack/2` for MAVLink 2.0 messages with signing support
- Use atoms for MAVLink enum values (e.g., `:video_stream_status_flags_running`) not integers

## Architecture Guidelines

### OTP and Supervision

- The application uses standard OTP supervision tree under `AnnouncerEx.Application`
- `AnnouncerEx.CameraManager` is a GenServer managing camera lifecycle
- **Never** use raw processes, **always** use GenServer or other OTP behaviors
- Crash recovery is handled automatically by the supervisor
- **Always** use named processes for singleton GenServers (e.g., `name: __MODULE__`)

### Network Communication

- UDP communication is handled via `:gen_udp` Erlang module
- **Always** configure socket with `[active: true, binary: true]` for async message reception
- Handle `{:udp, socket, host, port, data}` messages in GenServer callbacks
- Router connection uses environment-configured host/port (see `AnnouncerEx.Config`)

### Message Handling

- Incoming MAVLink commands are routed to `AnnouncerEx.CommandHandler`
- Message building is centralized in `AnnouncerEx.MessageBuilder`
- **Always** validate MAVLink message structure before processing
- **Always** send acknowledgments for command messages
- Unsupported commands should return `MAV_RESULT_UNSUPPORTED` acknowledgment

### Testing Guidelines

- Write tests for all command handlers
- Mock UDP sockets using test helpers
- Test MAVLink message encoding/decoding
- Verify correct component IDs and system IDs in responses
- Test heartbeat timing and reliability
- **Always** test error cases and invalid message handling

## Deployment and Debugging

### Deployment Pipeline

- All deployments are done via GitHub workflows (see [.github/workflows/process-announcer-ex.yaml](.github/workflows/process-announcer-ex.yaml))
- Images are built and pushed to GitHub Container Registry (GHCR)
- Flux CD automatically pulls and deploys new images to the cluster
- Deployment manifests are in [deployments/apps/announcer-ex-deployment.yaml](deployments/apps/announcer-ex-deployment.yaml)
- **Never** manually deploy - always use the GitHub workflow pipeline
- Temporary manual deployments can be done for debugging purposes, but must be reversed after the issue is resolved

### Debugging Running Instances

The application runs in a Kubernetes cluster with context `rpiuav` and namespace `rpiuav`.

**Common kubectl commands for debugging:**

```bash
# Set context (if not already set)
kubectl config use-context rpiuav

# Check pod status
kubectl get pods -n rpiuav -l app=announcer-ex-replicaset

# View logs (follow mode)
kubectl logs -n rpiuav -l app=announcer-ex-replicaset -f

# View logs for specific time range
kubectl logs -n rpiuav -l app=announcer-ex-replicaset --since=1h

# Get pod details and events
kubectl describe pod -n rpiuav -l app=announcer-ex-replicaset

# Execute commands in running pod
kubectl exec -n rpiuav -l app=announcer-ex-replicaset -it -- /bin/sh

# View environment variables
kubectl exec -n rpiuav -l app=announcer-ex-replicaset -- env

# Check deployment status
kubectl get deployment announcer-ex -n rpiuav

# View deployment details
kubectl describe deployment announcer-ex -n rpiuav

# Check current image version
kubectl get deployment announcer-ex -n rpiuav -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Configuration sources:**

- Environment variables are set in the deployment manifest
- `CAMERA_URL` and `SYSTEM_ID` come from the `rpi4-config` ConfigMap
- Other variables are hardcoded in the deployment spec

**To debug MAVLink communication:**

```bash
# Check if announcer is sending heartbeats
kubectl logs -n rpiuav -l app=announcer-ex-replicaset | grep -i heartbeat

# Monitor MAVLink messages
kubectl logs -n rpiuav -l app=announcer-ex-replicaset -f | grep -i "mavlink\|command\|message"
```

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

  ```elixir
  i = 0
  mylist = ["blue", "green"]
  mylist[i]
  ```

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

  ```elixir
  i = 0
  mylist = ["blue", "green"]
  Enum.at(mylist, i)
  ```

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

  ```elixir
  # INVALID: we are rebinding inside the `if` and the result never gets assigned
  if connected?(socket) do
    socket = assign(socket, :val, val)
  end

  # VALID: we rebind the result of the `if` to a new variable
  socket =
    if connected?(socket) do
      assign(socket, :val, val)
    end
  ```

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field`
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- usage-rules-end -->
