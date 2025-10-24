# Router-Ex Testing Guide

This guide provides comprehensive testing procedures for Router-Ex during implementation and validation.

---

## Table of Contents

1. [Test Strategy](#test-strategy)
2. [Unit Testing](#unit-testing)
3. [Integration Testing](#integration-testing)
4. [Compatibility Testing](#compatibility-testing)
5. [Performance Testing](#performance-testing)
6. [Hardware Testing](#hardware-testing)
7. [Test Tools and Utilities](#test-tools-and-utilities)

---

## Test Strategy

### Testing Pyramid

```
         ┌─────────────┐
         │   Manual    │ (5%)
         │   Testing   │
         ├─────────────┤
         │ Integration │ (15%)
         │   Tests     │
         ├─────────────┤
         │    Unit     │ (80%)
         │   Tests     │
         └─────────────┘
```

### Test Coverage Goals
- **Overall Coverage:** >80%
- **Core Modules:** >90% (RouterCore, MessageFilter, ConfigManager)
- **Connection Handlers:** >70%
- **Critical Paths:** 100% (message routing, configuration parsing)

### Test Levels

1. **Unit Tests:** Test individual modules in isolation
2. **Integration Tests:** Test component interactions
3. **Compatibility Tests:** Verify parity with mavlink-router
4. **Performance Tests:** Validate latency and throughput
5. **Hardware Tests:** Test on actual Raspberry Pi hardware

---

## Unit Testing

### Setup

```elixir
# test/test_helper.exs
ExUnit.start()

# Mock modules for testing
defmodule RouterEx.TestHelpers do
  def create_test_frame(opts \\ []) do
    %XMAVLink.Frame{
      source_system: opts[:source_system] || 1,
      source_component: opts[:source_component] || 1,
      target_system: opts[:target_system] || 0,
      target_component: opts[:target_component] || 0,
      message_id: opts[:message_id] || 0,
      payload: opts[:payload] || <<>>,
      message: opts[:message] || %{}
    }
  end

  def create_mock_connection(type, name) do
    {type, name}
  end
end
```

### Module-Level Tests

#### ConfigManager Tests

```elixir
defmodule RouterEx.ConfigManagerTest do
  use ExUnit.Case
  alias RouterEx.ConfigManager

  describe "parse_config/1" do
    test "parses general section" do
      config = """
      [General]
      TcpServerPort=5760
      ReportStats=true
      MavlinkDialect=auto
      """

      result = ConfigManager.parse_config(config)

      assert result.general.tcp_server_port == 5760
      assert result.general.report_stats == true
      assert result.general.mavlink_dialect == :auto
    end

    test "parses UART endpoint" do
      config = """
      [UartEndpoint FlightController]
      Device = /dev/serial0
      Baud = 921600
      """

      result = ConfigManager.parse_config(config)

      assert length(result.endpoints) == 1
      endpoint = hd(result.endpoints)
      assert endpoint.type == :uart
      assert endpoint.device == "/dev/serial0"
      assert endpoint.baud == 921600
    end

    test "parses UDP server endpoint with filtering" do
      config = """
      [UdpEndpoint video0]
      Mode = Server
      Address = 0.0.0.0
      Port = 14560
      AllowMsgIdOut = 0,4,76,322,323
      """

      result = ConfigManager.parse_config(config)

      endpoint = hd(result.endpoints)
      assert endpoint.type == :udp_server
      assert endpoint.mode == :server
      assert endpoint.port == 14560
      assert endpoint.allow_msg_ids == [0, 4, 76, 322, 323]
    end

    test "handles invalid configuration gracefully" do
      config = """
      [InvalidSection]
      InvalidKey = InvalidValue
      """

      assert_raise RuntimeError, fn ->
        ConfigManager.parse_config(config)
      end
    end
  end
end
```

#### RouterCore Tests

```elixir
defmodule RouterEx.RouterCoreTest do
  use ExUnit.Case
  alias RouterEx.RouterCore
  import RouterEx.TestHelpers

  setup do
    {:ok, router} = start_supervised(RouterCore)
    %{router: router}
  end

  describe "connection management" do
    test "registers connection", %{router: _router} do
      conn_id = create_mock_connection(:test, "test1")
      conn_info = %{pid: self(), type: :test}

      assert :ok = RouterCore.register_connection(conn_id, conn_info)
    end

    test "unregisters connection", %{router: _router} do
      conn_id = create_mock_connection(:test, "test1")
      conn_info = %{pid: self(), type: :test}

      RouterCore.register_connection(conn_id, conn_info)
      assert :ok = RouterCore.unregister_connection(conn_id)
    end
  end

  describe "message routing" do
    setup %{router: _router} do
      # Register test connections
      conn_a = create_mock_connection(:test, "conn_a")
      conn_b = create_mock_connection(:test, "conn_b")

      RouterCore.register_connection(conn_a, %{pid: self(), type: :test})
      RouterCore.register_connection(conn_b, %{pid: self(), type: :test})

      %{conn_a: conn_a, conn_b: conn_b}
    end

    test "broadcasts message with target_system = 0", %{conn_a: conn_a, conn_b: _conn_b} do
      frame = create_test_frame(source_system: 1, target_system: 0)

      RouterCore.route_message(conn_a, frame)

      # Should receive message on conn_b but not conn_a
      assert_receive {:send_frame, ^frame}, 1000
    end

    test "routes targeted message to correct connection", %{conn_a: conn_a, conn_b: conn_b} do
      # First, establish that conn_b knows about system 2
      frame_from_sys2 = create_test_frame(source_system: 2, target_system: 0)
      RouterCore.route_message(conn_b, frame_from_sys2)

      # Clear mailbox
      flush_mailbox()

      # Now send targeted message from conn_a to system 2
      frame_to_sys2 = create_test_frame(source_system: 1, target_system: 2)
      RouterCore.route_message(conn_a, frame_to_sys2)

      # Should only be sent to conn_b
      assert_receive {:send_frame, ^frame_to_sys2}, 1000
    end

    test "does not route back to source", %{conn_a: conn_a} do
      frame = create_test_frame(source_system: 1, target_system: 0)

      RouterCore.route_message(conn_a, frame)

      # Should not receive message back
      refute_receive {:send_frame, _}, 100
    end
  end

  describe "statistics" do
    test "tracks message counts", %{router: _router, conn_a: conn_a} do
      frame = create_test_frame()
      RouterCore.route_message(conn_a, frame)

      stats = RouterCore.get_stats()
      assert stats.packets_received >= 1
    end
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
```

#### MessageFilter Tests

```elixir
defmodule RouterEx.MessageFilterTest do
  use ExUnit.Case
  alias RouterEx.MessageFilter
  import RouterEx.TestHelpers

  describe "should_forward?/2" do
    test "allows all messages when no filters configured" do
      frame = create_test_frame(message_id: 123)
      config = %{}

      assert MessageFilter.should_forward?(frame, config)
    end

    test "allows only whitelisted messages" do
      config = %{allow_msg_ids: [0, 4, 76]}

      assert MessageFilter.should_forward?(create_test_frame(message_id: 0), config)
      assert MessageFilter.should_forward?(create_test_frame(message_id: 4), config)
      refute MessageFilter.should_forward?(create_test_frame(message_id: 123), config)
    end

    test "blocks blacklisted messages" do
      config = %{block_msg_ids: [100, 101, 102]}

      refute MessageFilter.should_forward?(create_test_frame(message_id: 100), config)
      assert MessageFilter.should_forward?(create_test_frame(message_id: 0), config)
    end

    test "whitelist takes precedence over blacklist" do
      config = %{
        allow_msg_ids: [0, 4, 76],
        block_msg_ids: [0]  # Try to block an allowed message
      }

      # Whitelist should win
      refute MessageFilter.should_forward?(create_test_frame(message_id: 0), config)
    end
  end
end
```

---

## Integration Testing

### Full Message Flow Test

```elixir
defmodule RouterEx.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  setup do
    # Start full application
    {:ok, _} = Application.ensure_all_started(:router_ex)

    on_exit(fn ->
      Application.stop(:router_ex)
    end)

    :ok
  end

  test "complete message flow from serial to UDP" do
    # This would require mocking or actual hardware
    # Skipped in CI, run manually
  end

  test "configuration reload updates routing" do
    # Test dynamic configuration reload
  end
end
```

### Connection Handler Tests

```elixir
defmodule RouterEx.Endpoint.UDPServerTest do
  use ExUnit.Case
  alias RouterEx.Endpoint.UDPServer

  @moduletag :integration

  test "accepts connections from multiple clients" do
    config = %{
      name: "test_udp",
      type: :udp_server,
      address: "127.0.0.1",
      port: 14999
    }

    {:ok, server} = start_supervised({UDPServer, config})

    # Send from client 1
    {:ok, client1} = :gen_udp.open(0, [:binary])
    :gen_udp.send(client1, {127, 0, 0, 1}, 14999, "test message")

    # Send from client 2
    {:ok, client2} = :gen_udp.open(0, [:binary])
    :gen_udp.send(client2, {127, 0, 0, 1}, 14999, "test message 2")

    # Verify both clients are tracked
    # (would need introspection API)

    :gen_udp.close(client1)
    :gen_udp.close(client2)
  end
end
```

---

## Compatibility Testing

### Side-by-Side Comparison with mavlink-router

**Objective:** Verify Router-Ex behaves identically to mavlink-router

**Setup:**
1. Run mavlink-router with specific configuration
2. Run Router-Ex with same configuration
3. Send identical MAVLink messages to both
4. Compare outputs

**Test Procedure:**

```bash
# Terminal 1: Start mavlink-router
mavlink-router /etc/mavlink-router/main.conf

# Terminal 2: Start Router-Ex
docker run -it --rm router-ex:test

# Terminal 3: Send test messages
python3 test_mavlink_sender.py --target localhost:14550

# Terminal 4: Monitor outputs
tcpdump -i any -n udp port 14560 -X
```

**Test Cases:**

1. **Heartbeat Routing**
   - Send HEARTBEAT from serial
   - Verify forwarded to all UDP endpoints

2. **Targeted Message Routing**
   - Send COMMAND_LONG to specific system/component
   - Verify only routed to aware connections

3. **Message Filtering**
   - Configure AllowMsgIdOut = 0,4,76,322,323
   - Send various message types
   - Verify only allowed messages forwarded

4. **Multi-Client Support**
   - Connect 3+ clients to UDP server
   - Verify all receive broadcasts
   - Verify targeted messages only to correct clients

**Success Criteria:**
- [ ] 100% message routing behavior match
- [ ] Same messages forwarded/filtered
- [ ] Similar performance characteristics
- [ ] No message loss

---

## Performance Testing

### Latency Measurement

**Test:** Measure time from message arrival to forwarding

```elixir
defmodule RouterEx.Performance.LatencyTest do
  use ExUnit.Case

  @tag :performance
  test "routing latency under 2ms" do
    # Start router
    {:ok, _} = Application.ensure_all_started(:router_ex)

    # Register connections
    conn_in = {:test, "input"}
    conn_out = {:test, "output"}

    RouterEx.RouterCore.register_connection(conn_in, %{pid: self(), type: :test})
    RouterEx.RouterCore.register_connection(conn_out, %{pid: self(), type: :test})

    # Measure routing time
    frame = RouterEx.TestHelpers.create_test_frame()

    {time_us, _} = :timer.tc(fn ->
      RouterEx.RouterCore.route_message(conn_in, frame)
      assert_receive {:send_frame, ^frame}, 100
    end)

    time_ms = time_us / 1000

    IO.puts("Routing latency: #{time_ms}ms")
    assert time_ms < 2.0, "Routing took #{time_ms}ms, expected <2ms"
  end
end
```

### Throughput Measurement

```bash
# Benchmark script
# Sends N messages and measures throughput

#!/bin/bash

NUM_MESSAGES=10000

start_time=$(date +%s.%N)

for i in $(seq 1 $NUM_MESSAGES); do
  echo "HEARTBEAT" | nc -u localhost 14550
done

end_time=$(date +%s.%N)

duration=$(echo "$end_time - $start_time" | bc)
throughput=$(echo "$NUM_MESSAGES / $duration" | bc -l)

echo "Throughput: $throughput msg/s"
```

**Success Criteria:**
- [ ] Routing latency: <2ms (target <1ms)
- [ ] Throughput: >5000 msg/s (target >10000 msg/s)
- [ ] CPU usage: <50% under load
- [ ] Memory stable over time (no leaks)

### Load Testing

```elixir
defmodule RouterEx.Performance.LoadTest do
  use ExUnit.Case

  @tag :load
  @tag timeout: :infinity
  test "sustained load for 1 hour" do
    {:ok, _} = Application.ensure_all_started(:router_ex)

    # Spawn multiple message senders
    num_senders = 10
    messages_per_sender = 100_000

    tasks = for _i <- 1..num_senders do
      Task.async(fn ->
        send_messages(messages_per_sender)
      end)
    end

    # Wait for completion
    Task.await_many(tasks, :infinity)

    # Check for memory leaks
    memory = :erlang.memory(:total)
    IO.puts("Final memory: #{memory / 1024 / 1024} MB")

    # Verify router still responsive
    stats = RouterEx.RouterCore.get_stats()
    assert stats.packets_received > 0
  end

  defp send_messages(count) do
    frame = RouterEx.TestHelpers.create_test_frame()
    conn = {:test, "sender_#{:rand.uniform(1000)}"}

    for _i <- 1..count do
      RouterEx.RouterCore.route_message(conn, frame)
    end
  end
end
```

---

## Hardware Testing

### Test Setup

**Required Hardware:**
- Raspberry Pi CM4/CM5
- Flight controller (Pixhawk/ArduPilot)
- Serial cable (USB-to-UART or direct connection)
- Network connection to GCS computer

**Software:**
- Router-Ex deployed to Pi
- QGroundControl on laptop
- MAVLink inspector tools

### Test Procedures

#### 1. Serial Connection Test

**Objective:** Verify serial communication with flight controller

**Steps:**
1. Connect flight controller to /dev/serial0
2. Deploy Router-Ex to Pi
3. Check logs for successful connection
4. Verify heartbeats received from FC
5. Send command to FC and verify response

**Verification:**
```bash
# Check Router-Ex logs
kubectl logs -n rpiuav deployment/router-ex

# Should see:
# [info] Starting serial endpoint: FlightController on /dev/serial0 @ 921600
# [info] Serial port /dev/serial0 opened successfully
# [debug] Received HEARTBEAT from system 1/1
```

#### 2. UDP Server Test

**Objective:** Verify announcer-ex can connect

**Steps:**
1. Deploy Router-Ex
2. Deploy announcer-ex
3. Verify announcer-ex connects to port 14560
4. Check that camera announcements are routed to GCS

**Verification:**
```bash
# Check if announcer-ex can connect
kubectl logs -n rpiuav deployment/announcer-ex

# Should see camera info broadcasts
# Check GCS receives camera component
```

#### 3. End-to-End Test

**Objective:** Verify complete system integration

**Steps:**
1. Deploy full stack (router-ex, announcer-ex, video-streamer)
2. Connect QGroundControl from laptop
3. Verify all MAVLink components appear in QGC
4. Send commands from QGC to FC
5. Verify video stream works
6. Check camera component responds to commands

**Success Criteria:**
- [ ] Flight controller appears in QGC
- [ ] Camera component appears in QGC
- [ ] Can send commands to FC
- [ ] Can control camera (if applicable)
- [ ] Video stream works
- [ ] Telemetry updates in real-time
- [ ] No message loss
- [ ] Stable operation for 30+ minutes

---

## Test Tools and Utilities

### MAVLink Message Generator

```python
# test_tools/mavlink_sender.py
from pymavlink import mavutil
import time
import argparse

def send_heartbeats(connection_string, count=100):
    """Send test heartbeat messages"""
    mav = mavutil.mavlink_connection(connection_string)

    for i in range(count):
        mav.mav.heartbeat_send(
            mavutil.mavlink.MAV_TYPE_GCS,
            mavutil.mavlink.MAV_AUTOPILOT_INVALID,
            0, 0, 0
        )
        time.sleep(1)
        print(f"Sent heartbeat {i+1}/{count}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", default="udp:localhost:14550")
    parser.add_argument("--count", type=int, default=100)
    args = parser.parse_args()

    send_heartbeats(args.target, args.count)
```

### Message Inspector

```python
# test_tools/mavlink_inspector.py
from pymavlink import mavutil
import argparse

def inspect_messages(connection_string):
    """Monitor and display MAVLink messages"""
    mav = mavutil.mavlink_connection(connection_string)

    print(f"Listening on {connection_string}")
    print("=" * 80)

    while True:
        msg = mav.recv_match(blocking=True)
        if msg:
            print(f"[{msg.get_srcSystem()}/{msg.get_srcComponent()}] {msg.get_type()}: {msg}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="udp:localhost:14550")
    args = parser.parse_args()

    inspect_messages(args.source)
```

### Performance Profiler

```elixir
# mix run scripts/profile_router.exs
Mix.install([{:router_ex, path: "."}])

# Start router
{:ok, _} = Application.ensure_all_started(:router_ex)

# Profile routing function
:fprof.trace([:start, {:procs, :all}])

# Run test workload
for _i <- 1..10_000 do
  frame = RouterEx.TestHelpers.create_test_frame()
  RouterEx.RouterCore.route_message({:test, "test"}, frame)
end

:fprof.trace(:stop)
:fprof.profile()
:fprof.analyse(dest: 'profile_results.txt')

IO.puts("Profile saved to profile_results.txt")
```

---

## Continuous Integration

### GitHub Actions Test Workflow

```yaml
# .github/workflows/test-router-ex.yaml
name: Test Router-Ex

on:
  pull_request:
    paths:
      - 'apps/router_ex/**'
  push:
    branches:
      - main

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '28'

      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: apps/router_ex/deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

      - name: Install dependencies
        run: |
          cd apps/router_ex
          mix deps.get

      - name: Run tests
        run: |
          cd apps/router_ex
          mix test --cover

      - name: Check formatting
        run: |
          cd apps/router_ex
          mix format --check-formatted

      - name: Run Credo
        run: |
          cd apps/router_ex
          mix credo --strict
```

---

## Test Execution Checklist

### Pre-Implementation Testing
- [ ] Set up test infrastructure
- [ ] Create test helpers and utilities
- [ ] Write example unit tests for each module

### During Implementation (Per Phase)
- [ ] Write unit tests for new modules
- [ ] Achieve >80% coverage for phase code
- [ ] Run integration tests
- [ ] Update test documentation

### Phase 5 (Dedicated Testing Phase)
- [ ] Complete all unit tests
- [ ] Complete all integration tests
- [ ] Run compatibility tests vs mavlink-router
- [ ] Execute performance benchmarks
- [ ] Run load tests
- [ ] Test on actual hardware
- [ ] Document all test results

### Pre-Production
- [ ] Final integration test on hardware
- [ ] 24-hour stability test
- [ ] Performance validation
- [ ] Security review
- [ ] User acceptance testing

---

**Document Version:** 1.0
**Last Updated:** 2025-10-23
**Status:** Template - Ready for use during implementation
