# Router-Ex Implementation Checklist

This checklist provides a detailed breakdown of all tasks required to implement Router-Ex, organized by phase.

## Phase 1: Project Setup & Basic Router (Week 1-2)

### 1.1 Project Initialization
- [ ] Create new Elixir application: `mix new router_ex --sup`
- [ ] Configure mix.exs with dependencies (xmavlink, circuits_uart, telemetry)
- [ ] Set up Elixir version requirement (1.18+)
- [ ] Add project metadata (description, licenses, links)
- [ ] Create .gitignore for Elixir project
- [ ] Initialize ExDoc for documentation
- [ ] Set up formatter configuration (.formatter.exs)

### 1.2 Application Structure
- [ ] Create lib/router_ex/application.ex with supervision tree
- [ ] Define application callback (start/2)
- [ ] Set up child supervisor structure
- [ ] Configure application environment in config/config.exs
- [ ] Create config/runtime.exs for runtime configuration
- [ ] Add dev.exs, test.exs, prod.exs configuration files

### 1.3 Configuration Management
- [ ] Create RouterEx.ConfigManager module
- [ ] Implement INI-style config parser
- [ ] Support [General] section parsing
- [ ] Support [UartEndpoint] parsing
- [ ] Support [UdpEndpoint] parsing
- [ ] Support [TcpEndpoint] parsing (if needed)
- [ ] Parse AllowMsgIdOut and BlockMsgIdOut
- [ ] Add configuration validation
- [ ] Implement config reload functionality
- [ ] Add unit tests for config parser
- [ ] Test with actual mavlink-router config file
- [ ] Handle malformed configuration gracefully

### 1.4 Router Core
- [ ] Create RouterEx.RouterCore GenServer
- [ ] Implement routing table (system_id -> connections)
- [ ] Implement connection registry
- [ ] Add register_connection/2 API
- [ ] Add unregister_connection/1 API
- [ ] Add route_message/2 API
- [ ] Implement basic routing logic
- [ ] Add message loop prevention
- [ ] Track message statistics
- [ ] Implement get_stats/0 API
- [ ] Add periodic stats reporting
- [ ] Write unit tests for routing logic
- [ ] Test routing table updates
- [ ] Test connection management

### 1.5 Telemetry Setup
- [ ] Create RouterEx.Telemetry module
- [ ] Define telemetry events
  - [ ] [:router_ex, :message, :received]
  - [ ] [:router_ex, :message, :routed]
  - [ ] [:router_ex, :message, :filtered]
  - [ ] [:router_ex, :connection, :opened]
  - [ ] [:router_ex, :connection, :closed]
- [ ] Set up telemetry_metrics
- [ ] Configure telemetry_poller for system metrics
- [ ] Add telemetry event documentation
- [ ] Create telemetry test helpers

### 1.6 Initial Testing
- [ ] Set up ExUnit test framework
- [ ] Create test helpers module
- [ ] Add mock connection utilities
- [ ] Write initial integration test
- [ ] Verify application starts successfully
- [ ] Test configuration loading
- [ ] Test basic routing without real connections

## Phase 2: Connection Handlers (Week 3-4)

### 2.1 Endpoint Supervisor
- [ ] Create RouterEx.Endpoint.Supervisor (DynamicSupervisor)
- [ ] Implement start_endpoint/1 function
- [ ] Add endpoint_child_spec/1 helper
- [ ] Handle endpoint crashes and restarts
- [ ] Add endpoint monitoring
- [ ] Test dynamic endpoint starting/stopping

### 2.2 Serial Connection Handler
- [ ] Create RouterEx.Endpoint.Serial module
- [ ] Add Circuits.UART dependency
- [ ] Implement init/1 with UART.start_link
- [ ] Add UART.open with device and baud configuration
- [ ] Handle {:circuits_uart, port, data} messages
- [ ] Implement MAVLink frame buffering
- [ ] Add frame parsing from serial stream
- [ ] Implement {:send_frame, frame} handler
- [ ] Add automatic reconnection on disconnect
- [ ] Handle UART errors gracefully
- [ ] Register/unregister with RouterCore
- [ ] Add serial port configuration validation
- [ ] Write unit tests with mock UART
- [ ] Test on actual hardware (/dev/serial0)
- [ ] Test with flight controller connection
- [ ] Verify bidirectional communication

### 2.3 UDP Server Handler
- [ ] Create RouterEx.Endpoint.UDPServer module
- [ ] Implement :gen_udp.open with port binding
- [ ] Handle {:udp, socket, ip, port, data} messages
- [ ] Track multiple clients in state
- [ ] Parse MAVLink packets from UDP data
- [ ] Implement broadcast to all clients
- [ ] Add client timeout/cleanup (remove stale clients)
- [ ] Implement {:send_frame, frame} handler
- [ ] Register/unregister with RouterCore
- [ ] Add port conflict handling
- [ ] Test with multiple simultaneous clients
- [ ] Test with announcer-ex connection
- [ ] Verify message filtering works

### 2.4 UDP Client Handler
- [ ] Create RouterEx.Endpoint.UDPClient module
- [ ] Implement :gen_udp.open for sending
- [ ] Parse destination IP address
- [ ] Handle {:udp, socket, ip, port, data} for responses
- [ ] Implement fixed-destination sending
- [ ] Add network error handling
- [ ] Register/unregister with RouterCore
- [ ] Test with GCS connection (10.10.10.70:14550)
- [ ] Verify outbound message delivery

### 2.5 TCP Server Handler
- [ ] Create RouterEx.Endpoint.TCPServer module
- [ ] Implement :gen_tcp.listen on configured port
- [ ] Accept incoming connections
- [ ] Spawn per-client connection handler
- [ ] Create RouterEx.Endpoint.TCPClient module
- [ ] Handle TCP client data reception
- [ ] Parse MAVLink frames from TCP stream
- [ ] Implement per-client buffering
- [ ] Handle client disconnections
- [ ] Track active TCP clients
- [ ] Implement broadcast to TCP clients
- [ ] Add TCP connection limits (if needed)
- [ ] Test with QGroundControl TCP connection
- [ ] Test with multiple simultaneous QGC clients

### 2.6 Connection Integration
- [ ] Integrate all endpoint types with ConfigManager
- [ ] Test mixed endpoint scenarios
- [ ] Verify endpoint startup from configuration
- [ ] Test endpoint crash recovery
- [ ] Add connection health monitoring
- [ ] Implement connection status reporting

## Phase 3: Message Routing & Filtering (Week 5)

### 3.1 Message Parser
- [ ] Create RouterEx.MessageParser module
- [ ] Implement stateful MAVLink frame parser
- [ ] Support MAVLink 1.0 parsing
- [ ] Support MAVLink 2.0 parsing
- [ ] Handle partial frames (buffering)
- [ ] Implement frame recovery after errors
- [ ] Add CRC validation
- [ ] Support message signing (MAVLink 2)
- [ ] Add parser state tests
- [ ] Test with corrupt data
- [ ] Test with mixed MAVLink 1/2 streams
- [ ] Benchmark parsing performance

### 3.2 Message Filter
- [ ] Create RouterEx.MessageFilter module
- [ ] Implement should_forward?/2 function
- [ ] Add AllowMsgIdOut filtering (whitelist)
- [ ] Add BlockMsgIdOut filtering (blacklist)
- [ ] Support message ID ranges (future)
- [ ] Add filter configuration validation
- [ ] Test filter combinations
- [ ] Verify video endpoint filtering (0,4,76,322,323)

### 3.3 Enhanced Routing
- [ ] Extend routing table to track components
- [ ] Implement system/component pair routing
- [ ] Add support for broadcast to all systems (target=0)
- [ ] Add support for broadcast to all components (target_component=0)
- [ ] Implement targeted message routing
- [ ] Add routing table introspection API
- [ ] Test complex routing scenarios
- [ ] Verify no routing loops

### 3.4 Message Deduplication
- [ ] Add message signature tracking (optional)
- [ ] Implement deduplication window
- [ ] Add duplicate detection
- [ ] Test deduplication effectiveness
- [ ] Measure performance impact

### 3.5 Advanced Features
- [ ] Add connection grouping support (optional)
- [ ] Implement shared system awareness for groups
- [ ] Add message rate limiting (optional)
- [ ] Implement priority queueing (optional)

### 3.6 Integration Testing
- [ ] Test full message flow: Serial → Router → UDP
- [ ] Test bidirectional routing
- [ ] Test multi-client scenarios
- [ ] Test message filtering end-to-end
- [ ] Verify compatibility with announcer-ex
- [ ] Test with actual flight controller

## Phase 4: Containerization & Deployment (Week 6)

### 4.1 Dockerfile
- [ ] Create multi-stage Dockerfile
- [ ] Configure builder stage with Elixir/Alpine
- [ ] Add build dependencies
- [ ] Configure prod release build
- [ ] Create minimal runtime stage
- [ ] Copy release to runtime
- [ ] Add healthcheck
- [ ] Set correct entrypoint
- [ ] Test local Docker build
- [ ] Test container on ARM64 architecture
- [ ] Verify serial port access in container
- [ ] Optimize image size

### 4.2 Release Configuration
- [ ] Configure mix release in mix.exs
- [ ] Set up runtime configuration
- [ ] Add release overlays (if needed)
- [ ] Configure release environment
- [ ] Test release build locally
- [ ] Verify release startup

### 4.3 Kubernetes Deployment
- [ ] Create router-ex-deployment.yaml
- [ ] Configure namespace (rpiuav)
- [ ] Set up pod labels and selectors
- [ ] Configure container ports (5760, 14550, 14560-14563)
- [ ] Add environment variables
- [ ] Configure ConfigMap mount (ROUTER_CONFIG)
- [ ] Set up serial device mount (/dev/serial0)
- [ ] Configure privileged security context
- [ ] Enable hostNetwork
- [ ] Set resource requests/limits
- [ ] Add liveness probe
- [ ] Add readiness probe
- [ ] Create Service definition
- [ ] Test deployment on k3s cluster
- [ ] Verify pod starts successfully
- [ ] Test serial port access in pod

### 4.4 CI/CD Pipeline
- [ ] Create .github/workflows/process-router-ex.yaml
- [ ] Configure build triggers (main branch, path filters)
- [ ] Set up Docker buildx for ARM64
- [ ] Configure GHCR push
- [ ] Add image tagging (date + git hash)
- [ ] Set up Kustomize for deployment updates
- [ ] Configure automatic manifest updates
- [ ] Test workflow end-to-end
- [ ] Verify automated deployment

### 4.5 Configuration Integration
- [ ] Verify ROUTER_CONFIG from rpi4-configmap works
- [ ] Test with existing configuration
- [ ] Add environment variable overrides
- [ ] Document configuration precedence
- [ ] Test configuration changes without rebuild

## Phase 5: Testing & Validation (Week 7)

### 5.1 Unit Tests
- [ ] Achieve >80% code coverage for core modules
- [ ] Test RouterCore routing logic
- [ ] Test ConfigManager parsing
- [ ] Test MessageFilter filtering
- [ ] Test MessageParser parsing
- [ ] Test all connection handlers
- [ ] Add property-based tests (StreamData)
- [ ] Test edge cases and error conditions

### 5.2 Integration Tests
- [ ] Test serial connection end-to-end
- [ ] Test UDP server with multiple clients
- [ ] Test UDP client outbound
- [ ] Test TCP server with QGC
- [ ] Test full routing flow
- [ ] Test configuration reload
- [ ] Test endpoint crash recovery
- [ ] Test application restart

### 5.3 Compatibility Tests
- [ ] Set up side-by-side comparison with mavlink-router
- [ ] Use identical configuration for both
- [ ] Compare message routing behavior
- [ ] Verify same messages forwarded
- [ ] Check for message loss
- [ ] Test with announcer-ex (should work with both)
- [ ] Test with actual flight controller
- [ ] Test with QGroundControl
- [ ] Verify video endpoint filtering matches

### 5.4 Performance Benchmarking
- [ ] Measure routing latency (target: <1ms)
- [ ] Measure throughput (target: >10k msg/s)
- [ ] Measure CPU usage (idle and under load)
- [ ] Measure memory usage
- [ ] Measure startup time
- [ ] Compare with mavlink-router benchmarks
- [ ] Identify and optimize bottlenecks
- [ ] Profile with :fprof or :eprof
- [ ] Consider NIFs for hot paths if needed

### 5.5 Load Testing
- [ ] Simulate high message rate (10k+ msg/s)
- [ ] Test with multiple simultaneous connections
- [ ] Test connection churn (frequent connect/disconnect)
- [ ] Monitor resource usage under load
- [ ] Test long-running stability (24h+ test)
- [ ] Check for memory leaks
- [ ] Verify graceful degradation

### 5.6 Hardware Testing
- [ ] Deploy to actual Raspberry Pi CM4/CM5
- [ ] Test with real flight controller
- [ ] Verify serial communication
- [ ] Test with ground control station
- [ ] Verify announcer-ex integration
- [ ] Test full system integration
- [ ] Monitor system resources on Pi

## Phase 6: Documentation (Week 8)

### 6.1 Code Documentation
- [ ] Add @moduledoc to all modules
- [ ] Add @doc to all public functions
- [ ] Add @typedoc for custom types
- [ ] Add @spec for function signatures
- [ ] Write comprehensive examples in docs
- [ ] Generate ExDoc documentation
- [ ] Review generated docs for completeness

### 6.2 README
- [ ] Write comprehensive README.md
- [ ] Add project overview
- [ ] Document features
- [ ] Add installation instructions
- [ ] Document configuration format
- [ ] Add usage examples
- [ ] Include troubleshooting section
- [ ] Add development instructions
- [ ] Link to additional documentation

### 6.3 Architecture Documentation
- [ ] Create docs/architecture.md
- [ ] Document high-level architecture
- [ ] Explain routing logic
- [ ] Describe connection handlers
- [ ] Document message flow
- [ ] Add architecture diagrams
- [ ] Explain design decisions
- [ ] Document extension points

### 6.4 Operations Guide
- [ ] Create docs/operations.md
- [ ] Document deployment procedures
- [ ] Add configuration examples
- [ ] Document monitoring and telemetry
- [ ] Add troubleshooting guide
- [ ] Document performance tuning
- [ ] Add operational checklists
- [ ] Include disaster recovery procedures

### 6.5 Migration Guide
- [ ] Create docs/migration.md
- [ ] Document migration steps from mavlink-router
- [ ] Add configuration migration guide
- [ ] Document compatibility notes
- [ ] Add rollback procedures
- [ ] Include migration checklist
- [ ] Document breaking changes (if any)
- [ ] Add FAQ section

### 6.6 Development Guide
- [ ] Create docs/development.md
- [ ] Document development setup
- [ ] Add testing guidelines
- [ ] Document contribution process
- [ ] Explain codebase structure
- [ ] Add debugging tips
- [ ] Document release process

### 6.7 API Documentation
- [ ] Document public API
- [ ] Add API examples
- [ ] Document telemetry events
- [ ] Document configuration schema
- [ ] Add API versioning notes

## Post-Implementation Tasks

### Cleanup
- [ ] Remove debug logging
- [ ] Clean up commented code
- [ ] Optimize code for production
- [ ] Run mix format on all files
- [ ] Run mix credo for code quality
- [ ] Fix all compiler warnings
- [ ] Update dependencies to latest versions

### Validation
- [ ] Final integration test on hardware
- [ ] Performance validation
- [ ] Security review
- [ ] Documentation review
- [ ] User acceptance testing

### Deployment
- [ ] Create initial release (v0.1.0)
- [ ] Tag release in git
- [ ] Build and push production image
- [ ] Deploy to staging environment
- [ ] Run smoke tests
- [ ] Deploy to production
- [ ] Monitor for issues

### Maintenance
- [ ] Set up issue tracking
- [ ] Create backlog for future enhancements
- [ ] Document known issues
- [ ] Plan for future phases

## Success Checklist

### Functional Criteria
- [ ] All connection types working (Serial, UDP, TCP)
- [ ] Message routing working correctly
- [ ] Message filtering working
- [ ] Compatible with existing configuration
- [ ] Works with announcer-ex
- [ ] Works with flight controller
- [ ] Works with QGroundControl

### Performance Criteria
- [ ] Routing latency <2ms
- [ ] Throughput >5000 msg/s
- [ ] CPU usage <15% idle
- [ ] Memory usage <150MB
- [ ] Startup time <5s

### Quality Criteria
- [ ] Test coverage >80%
- [ ] All tests passing
- [ ] No compiler warnings
- [ ] Documentation complete
- [ ] Code review passed

### Deployment Criteria
- [ ] Dockerfile builds successfully
- [ ] Container runs on ARM64
- [ ] Kubernetes deployment working
- [ ] CI/CD pipeline functional
- [ ] Production deployment successful

---

**Total Tasks:** ~215
**Estimated Effort:** 8 weeks
**Status:** Not Started
