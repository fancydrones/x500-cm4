# PRD-004: Router-Ex - Elixir MAVLink Router

**Status:** 📋 **PLANNED - NOT STARTED**
**Created:** 2025-10-23
**Target Start:** TBD
**Target Completion:** TBD (8 weeks from start)

---

## Overview

Router-Ex is an Elixir-based MAVLink message router that will replace the existing C/C++ mavlink-router implementation. It provides intelligent message routing between serial, UDP, and TCP connections while maintaining full compatibility with existing configurations and behaviors.

## Goals

### Primary Objectives
1. **Drop-in Replacement:** Compatible with existing mavlink-router configuration and behavior
2. **Unified Ecosystem:** Native integration with Elixir services (announcer-ex, video-streamer, companion)
3. **Enhanced Maintainability:** Easier to modify and extend than C/C++
4. **Improved Observability:** Rich telemetry and monitoring capabilities
5. **Fault Tolerance:** Leverage OTP supervision for automatic recovery

### Success Metrics
- Routing latency: <2ms per message
- Throughput: >5000 messages/second
- CPU usage: <15% idle, <50% under load
- Memory usage: <150MB
- 100% configuration compatibility with mavlink-router

## Architecture Highlights

```
┌─────────────────────────────────────────┐
│         Router-Ex Application           │
│                                         │
│  ┌─────────────────────────────────┐  │
│  │     Router Core (GenServer)      │  │
│  │  - Message routing logic         │  │
│  │  - System awareness tracking     │  │
│  │  - Message filtering             │  │
│  └─────────────────────────────────┘  │
│                                         │
│  ┌─────────────────────────────────┐  │
│  │   Connection Handlers            │  │
│  │  - Serial (UART)                 │  │
│  │  - UDP Server/Client             │  │
│  │  - TCP Server                    │  │
│  └─────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**Key Features:**
- MAVLink 1.0 and 2.0 protocol support
- Intelligent routing based on system awareness
- Message filtering (whitelist/blacklist)
- Automatic reconnection on connection loss
- Hot code reloading
- Comprehensive telemetry

## Implementation Phases

| Phase | Duration | Focus |
|-------|----------|-------|
| **Phase 1** | Week 1-2 | Project setup, config management, router core |
| **Phase 2** | Week 3-4 | Connection handlers (Serial, UDP, TCP) |
| **Phase 3** | Week 5 | Message routing, filtering, advanced features |
| **Phase 4** | Week 6 | Containerization, Kubernetes, CI/CD |
| **Phase 5** | Week 7 | Testing, benchmarking, validation |
| **Phase 6** | Week 8 | Documentation, migration guide |

**Total Timeline:** 8 weeks

## Documents

### Planning Documents
- **[Implementation Plan](implementation_plan.md)** - Complete technical specification and implementation guide
- **[Implementation Checklist](implementation_checklist.md)** - Detailed task breakdown (~215 tasks)

### Phase Completion Notes (To be created during implementation)
- Phase 1: Project setup and basic router
- Phase 2: Connection handlers
- Phase 3: Message routing and filtering
- Phase 4: Containerization and deployment
- Phase 5: Testing and validation
- Phase 6: Documentation

### Deliverables (To be created)
- Router-Ex application (`apps/router_ex/`)
- Docker container
- Kubernetes deployment manifests
- CI/CD pipeline
- Comprehensive documentation
- Migration guide from mavlink-router

## Technology Stack

**Core:**
- Elixir 1.18+
- XMAVLink ~> 0.5.0 (MAVLink protocol library)
- Circuits.UART ~> 1.5 (serial communication)

**Infrastructure:**
- Alpine Linux (container base)
- Kubernetes (k3s)
- GitHub Actions (CI/CD)

**Development:**
- ExUnit (testing)
- ExDoc (documentation)
- Telemetry (observability)

## Key Design Decisions

### Why Elixir?

**Benefits:**
1. **Ecosystem Integration:** Seamless integration with announcer-ex, video-streamer, and companion
2. **Fault Tolerance:** OTP supervision trees provide automatic recovery
3. **Hot Reloading:** Update routing logic without restart
4. **Developer Productivity:** Faster iteration and testing cycles
5. **Observability:** Built-in telemetry and logging

**Trade-offs:**
- Higher memory usage (~100-150MB vs ~10-20MB for C++)
- Slightly higher CPU usage (~10% vs ~5% idle)
- Acceptable for the benefits gained

### Configuration Formats

Router-Ex supports **multiple configuration formats** to provide the best developer experience:

**Recommended: Elixir Configuration** (native, type-safe)
```elixir
# config/runtime.exs
config :router_ex,
  endpoints: [
    %{name: "FlightController", type: :uart, device: "/dev/serial0", baud: 921_600},
    %{name: "video0", type: :udp_server, address: "0.0.0.0", port: 14560,
      allow_msg_ids: [0, 4, 76, 322, 323]},
    %{name: "GCS", type: :udp_client, address: "10.10.10.70", port: 14550}
  ]
```

**Also Supported:**
- **YAML** - Kubernetes-native, human-readable
- **TOML** - Modern alternative to INI
- **INI** - Backward compatibility with mavlink-router

**Priority:** Elixir > YAML > TOML > INI

See [configuration-formats.md](configuration-formats.md) for complete documentation and examples.

## Integration Points

### Upstream (Input Sources)
- **Flight Controller:** Serial connection (/dev/serial0)
- **Ground Control Station:** UDP/TCP connections

### Downstream (Output Destinations)
- **announcer-ex:** UDP port 14560 (camera component)
- **video-streamer:** Via announcer-ex
- **companion:** Web UI integration
- **External GCS:** QGroundControl, ATAK, etc.

### Configuration
- **rpi4-config ConfigMap:** ROUTER_CONFIG key contains configuration

## Comparison: mavlink-router vs Router-Ex

| Aspect | mavlink-router (C++) | Router-Ex (Elixir) |
|--------|---------------------|-------------------|
| **Language** | C/C++ | Elixir |
| **Memory** | ~10-20 MB | ~100-150 MB |
| **CPU (idle)** | <5% | <10% |
| **Latency** | <1ms | <2ms (target) |
| **Hot Reload** | ❌ No | ✅ Yes |
| **Supervision** | Manual | ✅ OTP |
| **Telemetry** | Basic | ✅ Rich |
| **Development** | Compile cycles | ✅ Interactive |
| **Integration** | Standalone | ✅ Native Elixir |
| **Maintainability** | Complex | ✅ Simpler |

**Recommendation:** Router-Ex provides better long-term value despite slightly higher resource usage.

## Dependencies

### Hardware
- Raspberry Pi CM4/CM5
- Serial port access (/dev/serial0)
- Network connectivity

### Software
- Existing Elixir infrastructure
- XMAVLink library
- Circuits.UART library
- K3s cluster

### External Services
- None (standalone service)

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Performance not meeting targets | Medium | High | Early benchmarking, optimize hot paths |
| Circuits.UART compatibility | Low | Medium | Test on hardware early |
| XMAVLink limitations | Low | Medium | Contribute upstream fixes |
| Memory overhead concerns | Low | Low | Profile early, optimize if needed |
| Configuration parsing complexity | Low | Medium | Comprehensive test coverage |

## Future Enhancements

### Post-MVP Features
1. **Message Logging:** Save MAVLink traffic for analysis
2. **Web Dashboard:** Real-time router status and statistics
3. **Advanced Filtering:** Regex patterns, rate limiting
4. **Hot Configuration Reload:** Update routes without restart
5. **MAVLink 2 Extensions:** Message signing, encryption

### Long-term Vision
- Unified MAVLink platform for all drone services
- Plugin system for custom message handlers
- Cloud telemetry integration
- Multi-drone routing support

## Getting Started (When Implementation Begins)

### Prerequisites
1. Elixir 1.18+ installed
2. Access to Raspberry Pi hardware
3. Familiarity with existing mavlink-router

### Implementation Steps
1. Review [Implementation Plan](implementation_plan.md)
2. Follow [Implementation Checklist](implementation_checklist.md)
3. Complete Phase 1 tasks
4. Document progress in phase completion notes
5. Continue through phases 2-6

### Development Workflow
1. Create feature branch
2. Implement tasks from checklist
3. Write tests (maintain >80% coverage)
4. Update documentation
5. Create PR with phase completion notes
6. Review and merge

## References

### Internal Documents
- [Implementation Plan](implementation_plan.md) - Complete technical specification
- [Implementation Checklist](implementation_checklist.md) - Task breakdown
- [PRD-002 Video Streamer](../002-video-streamer/implementation_plan.md) - Reference implementation

### External Resources
- [XMAVLink Documentation](https://hexdocs.pm/xmavlink)
- [MAVLink Protocol](https://mavlink.io/en/)
- [mavlink-router Repository](https://github.com/mavlink-router/mavlink-router)
- [Circuits.UART](https://hexdocs.pm/circuits_uart)

## Questions & Discussions

For questions or discussions about Router-Ex:
1. Review the Implementation Plan
2. Check the Implementation Checklist
3. Create an issue in the repository
4. Discuss in team meetings

## Status Updates

### Current Status: NOT STARTED
- ⏸️ Awaiting start date decision
- 📋 Planning complete
- 🎯 Ready for implementation

### Milestones (To be updated during implementation)
- [ ] Phase 1 Complete: Basic router infrastructure
- [ ] Phase 2 Complete: All connection handlers working
- [ ] Phase 3 Complete: Message routing and filtering
- [ ] Phase 4 Complete: Containerized and deployed
- [ ] Phase 5 Complete: Tested and validated
- [ ] Phase 6 Complete: Documentation finished
- [ ] Production deployment
- [ ] Migration from mavlink-router complete

---

**PRD Owner:** TBD
**Technical Lead:** TBD
**Target Users:** x500-cm4 UAV platform operators and developers

**Last Updated:** 2025-10-23
