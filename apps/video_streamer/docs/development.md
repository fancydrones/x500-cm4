# Video Streamer Development Guide

This guide covers development setup, contributing guidelines, testing procedures, and code standards for the video streaming service.

## Table of Contents

- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Contributing Guidelines](#contributing-guidelines)
- [Testing](#testing)
- [Code Style](#code-style)
- [Membrane Framework Concepts](#membrane-framework-concepts)
- [Pull Request Process](#pull-request-process)
- [Debugging](#debugging)

## Development Setup

### Prerequisites

**Required**:
- Elixir 1.18+ with Erlang/OTP 28+
- Git
- Docker (for containerized testing)
- Code editor with Elixir support (VS Code + ElixirLS recommended)

**Optional (for hardware testing)**:
- Raspberry Pi 4/5 with Camera Module (IMX477 or IMX219)
- SD card (16GB+) with Raspberry Pi OS
- Network access to test drone

### Initial Setup

```bash
# Clone repository
git clone https://github.com/fancydrones/x500-cm4.git
cd x500-cm4/apps/video_streamer

# Install dependencies
mix deps.get

# Compile
mix compile

# Run tests
mix test

# Run tests with coverage
mix test --cover

# Start IEx session (requires camera hardware)
iex -S mix
```

### Development Tools

**Recommended VS Code Extensions**:
- ElixirLS - Language server with IntelliSense
- Elixir Test - Test runner integration
- GitLens - Git blame and history
- Docker - Dockerfile support

**Useful Mix Tasks**:
```bash
# Format code
mix format

# Check for issues
mix credo

# Security analysis
mix deps.audit

# Dependency updates
mix hex.outdated

# Generate documentation
mix docs

# Analyze compilation
mix xref graph
```

### Editor Configuration

**VS Code settings.json**:
```json
{
  "elixirLS.projectDir": "apps/video_streamer",
  "elixirLS.dialyzerEnabled": true,
  "elixirLS.fetchDeps": false,
  "editor.formatOnSave": true,
  "[elixir]": {
    "editor.defaultFormatter": "JakeBecker.elixir-ls",
    "editor.tabSize": 2
  }
}
```

**.formatter.exs** (already configured):
```elixir
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 100
]
```

## Project Structure

```
apps/video_streamer/
├── lib/
│   ├── video_streamer/
│   │   ├── application.ex          # OTP application supervisor
│   │   ├── pipeline.ex              # Main Membrane pipeline
│   │   ├── pipeline_manager.ex     # Pipeline lifecycle management
│   │   ├── telemetry.ex             # Metrics and monitoring
│   │   └── rtsp/
│   │       ├── server.ex            # RTSP TCP server (Ranch)
│   │       ├── protocol.ex          # RTSP message parsing/building
│   │       └── sdp.ex               # SDP generation (RFC 4566/6184)
│   ├── membrane_rpicam/
│   │   └── source.ex                # Camera source with error handling
│   └── video_streamer.ex            # Main module (version, hello/0)
│
├── test/
│   ├── video_streamer/
│   │   └── rtsp/
│   │       ├── protocol_test.exs    # RTSP protocol tests
│   │       └── sdp_test.exs         # SDP generation tests
│   ├── video_streamer_test.exs      # Main module tests
│   └── test_helper.exs              # Test configuration
│
├── config/
│   ├── config.exs                   # Base configuration
│   ├── dev.exs                      # Development config
│   ├── test.exs                     # Test config (env: :test)
│   ├── prod.exs                     # Production config
│   └── runtime.exs                  # Runtime config (env vars)
│
├── docs/                            # Documentation
│   ├── architecture.md              # System architecture
│   ├── operations.md                # Ops guide
│   └── development.md               # This file
│
├── Dockerfile                       # Multi-stage production build
├── mix.exs                          # Project definition
├── mix.lock                         # Locked dependencies
├── .formatter.exs                   # Code formatting config
├── .gitignore                       # Git ignore patterns
└── README.md                        # User documentation
```

### Module Responsibilities

| Module | Type | Purpose |
|--------|------|---------|
| `VideoStreamer.Application` | Supervisor | Start/supervise top-level processes |
| `VideoStreamer.PipelineManager` | GenServer | Manage pipeline lifecycle, restarts |
| `VideoStreamer.Pipeline` | Membrane.Pipeline | Define multimedia processing graph |
| `VideoStreamer.RTSP.Server` | GenServer | Handle RTSP TCP connections |
| `VideoStreamer.RTSP.Protocol` | Module | Parse/build RTSP messages |
| `VideoStreamer.RTSP.SDP` | Module | Generate SDP descriptions |
| `VideoStreamer.Telemetry` | Supervisor | Telemetry setup |
| `Membrane.Rpicam.Source` | Membrane.Source | Camera capture with retry logic |

## Contributing Guidelines

### Code of Conduct

- Be respectful and constructive
- Focus on the issue, not the person
- Welcome newcomers and help them learn
- Follow the Elixir community guidelines

### Before Contributing

1. **Search existing issues** to avoid duplicates
2. **Discuss major changes** in an issue before coding
3. **Follow code style** (run `mix format`)
4. **Write tests** for new functionality
5. **Update documentation** for API changes

### Branch Naming

Use descriptive branch names:

```
feature/add-rtsp-authentication
fix/camera-retry-logic
docs/update-readme
refactor/pipeline-manager-state
test/sdp-generation
```

### Commit Messages

Follow conventional commits:

```
feat: add RTSP authentication support
fix: handle camera disconnection gracefully
docs: update architecture diagrams
refactor: simplify pipeline manager state
test: add SDP generation tests
chore: update dependencies
```

**Format**:
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`

### Example Commit

```
feat(rtsp): add basic authentication support

Implements RFC 2617 basic authentication for RTSP server.
Adds RTSP_AUTH, RTSP_USERNAME, RTSP_PASSWORD environment variables.

Closes #42
```

## Testing

### Test Organization

Tests are organized to match the source structure:

```
test/
├── video_streamer/
│   └── rtsp/
│       ├── protocol_test.exs      # Tests VideoStreamer.RTSP.Protocol
│       └── sdp_test.exs           # Tests VideoStreamer.RTSP.SDP
└── video_streamer_test.exs        # Tests VideoStreamer module
```

### Running Tests

```bash
# Run all tests
mix test

# Run specific file
mix test test/video_streamer/rtsp/protocol_test.exs

# Run specific test
mix test test/video_streamer/rtsp/protocol_test.exs:42

# Run with coverage
mix test --cover

# Run with trace (detailed output)
mix test --trace

# Watch mode (run on file changes, requires mix_test_watch)
mix test.watch
```

### Test Environment

Tests run with `env: :test` configuration (see `config/test.exs`):

- Camera and RTSP server are **not started** (avoids hardware dependencies)
- Only Telemetry supervisor runs
- Logger level set to `:warning` (quiet test output)

### Writing Tests

**Unit Test Example** (stateless module):

```elixir
defmodule VideoStreamer.RTSP.ProtocolTest do
  use ExUnit.Case, async: true  # async: true for stateless tests
  alias VideoStreamer.RTSP.Protocol

  describe "parse_request/1" do
    test "parses OPTIONS request" do
      request = """
      OPTIONS rtsp://10.10.10.2:8554/video RTSP/1.0\r
      CSeq: 1\r
      \r
      """

      assert {:ok, parsed} = Protocol.parse_request(request)
      assert parsed.method == "OPTIONS"
      assert parsed.uri == "rtsp://10.10.10.2:8554/video"
      assert parsed.headers["CSeq"] == "1"
    end

    test "returns error for malformed request" do
      request = "INVALID REQUEST"
      assert {:error, _reason} = Protocol.parse_request(request)
    end
  end
end
```

**Integration Test Example** (stateful component):

```elixir
defmodule VideoStreamer.PipelineManagerTest do
  use ExUnit.Case, async: false  # async: false for stateful tests

  setup do
    # Start pipeline manager for this test
    {:ok, pid} = VideoStreamer.PipelineManager.start_link([])
    %{manager_pid: pid}
  end

  test "starts pipeline on init", %{manager_pid: pid} do
    # Allow time for async initialization
    Process.sleep(100)

    pipeline_pid = VideoStreamer.PipelineManager.get_pipeline_pid()
    assert is_pid(pipeline_pid)
  end
end
```

**Property-Based Testing** (ExUnitProperties):

```elixir
defmodule VideoStreamer.RTSP.SDPPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "generate_sdp always returns valid SDP" do
    check all ip <- ip_address(),
              width <- integer(640..1920),
              height <- integer(480..1080),
              fps <- integer(15..60) do

      sdp = VideoStreamer.RTSP.SDP.generate_sdp(ip, "/video", %{
        width: width,
        height: height,
        framerate: fps
      })

      assert sdp =~ "v=0"
      assert sdp =~ "m=video"
      assert sdp =~ "a=rtpmap:96 H264/90000"
    end
  end
end
```

### Test Coverage

**Coverage goals**:
- Overall: >70% (currently ~40%, mainly protocol/SDP modules)
- Critical modules (Protocol, SDP): >80%
- GenServers/Supervisors: Best-effort (hard to test without mocking)

**View coverage**:
```bash
# Generate coverage report
mix test --cover

# HTML coverage report (requires excoveralls)
mix coveralls.html
open cover/excoveralls.html
```

### Mocking

For testing with external dependencies, use Mox:

```elixir
# In test_helper.exs
Mox.defmock(CameraMock, for: Membrane.Source)

# In test
setup do
  expect(CameraMock, :handle_playing, fn _ctx, state ->
    {[], state}
  end)
end
```

## Code Style

### Formatting

All code must be formatted with `mix format`:

```bash
# Format all files
mix format

# Check if formatted
mix format --check-formatted

# Format specific file
mix format lib/video_streamer/pipeline.ex
```

**Enforced in CI**: Pull requests fail if code is not formatted.

### Naming Conventions

**Modules**: PascalCase
```elixir
defmodule VideoStreamer.RTSP.Protocol do
```

**Functions**: snake_case
```elixir
def parse_request(binary) do
```

**Atoms**: snake_case
```elixir
:ok, :error, :playing, :camera_source
```

**Variables**: snake_case
```elixir
camera_pid, stream_config, client_info
```

**Module attributes**: snake_case with @
```elixir
@default_port 8554
@rtsp_version "RTSP/1.0"
```

### Documentation

**Module documentation**:
```elixir
defmodule VideoStreamer.RTSP.Protocol do
  @moduledoc """
  RTSP protocol message parsing and building.

  Implements RFC 2326 (RTSP) request/response handling.
  Provides functions to parse incoming requests and build responses.
  """
end
```

**Function documentation**:
```elixir
@doc """
Parses an RTSP request message.

## Parameters
  - binary: Raw RTSP request bytes

## Returns
  - `{:ok, request()}` on success
  - `{:error, term()}` on parse failure

## Examples

    iex> Protocol.parse_request("OPTIONS * RTSP/1.0\\r\\nCSeq: 1\\r\\n\\r\\n")
    {:ok, %{method: "OPTIONS", uri: "*", version: "RTSP/1.0", ...}}
"""
@spec parse_request(binary()) :: {:ok, request()} | {:error, term()}
def parse_request(binary) do
```

**Typespecs**: Always provide for public functions
```elixir
@type request() :: %{
  method: String.t(),
  uri: String.t(),
  version: String.t(),
  headers: map(),
  body: String.t()
}

@spec parse_request(binary()) :: {:ok, request()} | {:error, term()}
```

### Error Handling

**Use tagged tuples**:
```elixir
# Good
{:ok, result} or {:error, reason}

# Avoid (except for internal errors that should crash)
raise "Camera not found"
```

**Pattern matching**:
```elixir
case Protocol.parse_request(data) do
  {:ok, request} ->
    handle_request(request)

  {:error, reason} ->
    Logger.error("Failed to parse request: #{inspect(reason)}")
    {:error, :invalid_request}
end
```

**With statements** for sequential operations:
```elixir
with {:ok, request} <- Protocol.parse_request(data),
     {:ok, session} <- create_session(request),
     {:ok, response} <- build_response(session) do
  {:ok, response}
else
  {:error, reason} -> {:error, reason}
end
```

## Membrane Framework Concepts

### Pipeline Structure

Membrane pipelines are processing graphs:

```elixir
defmodule VideoStreamer.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _opts) do
    spec = [
      child(:camera, Membrane.Rpicam.Source)
      |> child(:parser, Membrane.H26x.Parser)
      |> child(:payloader, Membrane.RTP.H264.Payloader)
      |> child(:tee, Membrane.Tee.Parallel)
    ]

    {[spec: spec], %{clients: %{}}}
  end
end
```

### Elements

**Source** (produces data):
```elixir
defmodule Membrane.Rpicam.Source do
  use Membrane.Source

  def_output_pad :output, accepted_format: Membrane.RemoteStream

  @impl true
  def handle_playing(_ctx, state) do
    # Start producing buffers
    port = Port.open({:spawn, "rpicam-vid ..."}, [:binary])
    {[], %{state | port: port}}
  end

  @impl true
  def handle_info({port, {:data, data}}, _ctx, %{port: port} = state) do
    buffer = %Membrane.Buffer{payload: data}
    {[buffer: {:output, buffer}], state}
  end
end
```

**Filter** (transforms data):
```elixir
defmodule Membrane.H26x.Parser do
  use Membrane.Filter

  def_input_pad :input, accepted_format: Membrane.RemoteStream
  def_output_pad :output, accepted_format: %Membrane.H264{...}

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    # Parse H.264 NAL units
    parsed = parse_nal(buffer.payload)
    {[buffer: {:output, %{buffer | payload: parsed}}], state}
  end
end
```

**Sink** (consumes data):
```elixir
defmodule Membrane.UDP.Sink do
  use Membrane.Sink

  def_input_pad :input, accepted_format: _any

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    # Send to UDP socket
    :gen_udp.send(state.socket, state.dest_ip, state.dest_port, buffer.payload)
    {[], state}
  end
end
```

### Dynamic Children

Adding/removing children at runtime:

```elixir
# Add child
Membrane.Pipeline.execute_actions(self(), [
  spec: {
    get_child(:tee)
    |> via_out(Pad.ref(:output, client_id))
    |> child({:udp_sink, client_id}, %Membrane.UDP.Sink{
      destination_address: client_ip,
      destination_port: client_port
    })
  }
])

# Remove child
Membrane.Pipeline.execute_actions(self(), [
  remove_children: [{:udp_sink, client_id}]
])
```

### Callbacks

**Common pipeline callbacks**:
- `handle_init/2` - Pipeline initialization
- `handle_child_notification/3` - Message from child element
- `handle_info/3` - External message to pipeline

**Common element callbacks**:
- `handle_playing/2` - Element started
- `handle_buffer/4` - Process buffer (filters/sinks)
- `handle_demand/5` - Pull-mode demand signaling
- `handle_info/3` - External message to element

## Pull Request Process

### Before Opening PR

1. **Rebase on main**:
```bash
git fetch origin
git rebase origin/main
```

2. **Run checks**:
```bash
mix format --check-formatted
mix test
mix credo
```

3. **Update documentation** if needed

4. **Self-review** your changes

### PR Template

```markdown
## Description
Brief description of changes

## Motivation
Why is this change needed?

## Changes
- List key changes
- Highlight breaking changes

## Testing
How was this tested?

## Checklist
- [ ] Tests pass (`mix test`)
- [ ] Code formatted (`mix format`)
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (if user-facing)
```

### Review Process

1. **CI checks must pass** (tests, formatting, build)
2. **At least one approval** required
3. **Address review comments**
4. **Squash commits** if messy history
5. **Maintainer merges** when ready

### After Merge

1. **Delete branch**
2. **Deploy to test environment** (if applicable)
3. **Monitor for issues**

## Debugging

### IEx Debugging

**Start IEx with application**:
```bash
iex -S mix
```

**Useful IEx commands**:
```elixir
# List processes
Process.list() |> Enum.filter(&Process.alive?/1)

# Inspect pipeline
pid = VideoStreamer.PipelineManager.get_pipeline_pid()
:sys.get_state(pid)

# Trace messages
:sys.trace(pid, true)

# Observer (GUI process viewer)
:observer.start()
```

### Remote Debugging (on drone)

**Connect to running release**:
```bash
# SSH to drone
ssh pi@10.10.10.2

# Attach to running Elixir node
kubectl exec -it deployment/video-streamer -- bin/video_streamer remote
```

**Debug in remote shell**:
```elixir
# Get application state
Application.get_all_env(:video_streamer)

# Find pipeline
pid = Process.whereis(VideoStreamer.PipelineManager)

# Inspect state
:sys.get_state(pid)
```

### Logging

**Add debug logs**:
```elixir
require Logger

Logger.debug("Camera started with config: #{inspect(config)}")
Logger.info("Client connected: #{inspect(client_ip)}")
Logger.warning("Retry attempt #{retry_count}/3")
Logger.error("Camera failed: #{inspect(reason)}")
```

**Log levels**:
- `:debug` - Detailed debugging (not in production)
- `:info` - Informational (startup, connections)
- `:warning` - Warnings (retries, deprecations)
- `:error` - Errors (failures, exceptions)

### Debugging Tests

**Run with trace**:
```bash
mix test --trace
```

**Debug single test**:
```elixir
test "parses request" do
  request = build_request()
  IO.inspect(request, label: "Request")  # Debug output
  assert {:ok, parsed} = Protocol.parse_request(request)
  IO.inspect(parsed, label: "Parsed")    # Debug output
end
```

**IEx in test**:
```elixir
test "debug test" do
  require IEx; IEx.pry()  # Stops execution, opens IEx
  # Continue with test...
end
```

Run with:
```bash
MIX_ENV=test iex -S mix test --trace
```

### Common Issues

**Issue**: `** (UndefinedFunctionError) function Mix.env/0 is undefined`
**Solution**: Don't use `Mix.env/0` in runtime code, only compile-time

**Issue**: Tests hang indefinitely
**Solution**: Check for `async: false` conflicts, deadlocks, or infinite loops

**Issue**: Camera not found in tests
**Solution**: Tests run with `env: :test`, camera is not started

**Issue**: Membrane pipeline won't start
**Solution**: Check element compatibility, pad connections, spec syntax

---

For architecture details, see [architecture.md](architecture.md).
For operations, see [operations.md](operations.md).
