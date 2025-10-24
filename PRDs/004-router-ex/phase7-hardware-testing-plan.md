# Phase 7: Hardware Testing & Migration Plan

**Status**: ⏸️ PENDING (Requires Hardware Access)
**Prerequisite**: Phases 1-6 Complete (MVP scope)
**Blocking PRD Closure**: Yes - PRD-004 cannot be closed until Phase 7 is complete

## Executive Summary

Phases 1-6 of RouterEx development are complete, delivering a fully functional MVP with:
- 77 automated tests (100% pass rate)
- Comprehensive documentation (7,050+ lines)
- Production-ready Docker container (63MB)
- Complete CI/CD pipeline
- Strong test coverage on core modules (90.70% Parser, 84.52% RouterCore)

However, **PRD-004 cannot be closed** until RouterEx has been validated on real hardware and successfully migrated from the existing mavlink-router deployment.

## Why Phase 7 is Critical

As the user stated:
> "I need to test on real hardware and migrate first. Usually lots of errors surface during real testing."

Real-world testing typically reveals:
- Hardware-specific issues (serial port access, device permissions)
- Performance bottlenecks on resource-constrained devices
- Network configuration issues
- Timing and concurrency bugs
- Integration issues with existing systems
- Edge cases not covered by unit tests

## Phase 7 Objectives

1. **Validate RouterEx on target hardware** (Raspberry Pi CM4/CM5)
2. **Ensure compatibility** with existing flight controller and ground control station
3. **Successfully migrate** from mavlink-router without service disruption
4. **Fix all bugs** discovered during real-world testing
5. **Achieve production readiness** with performance validation

## Prerequisites

### Hardware Requirements
- ✅ Raspberry Pi CM4 or CM5
- ✅ Flight controller (Pixhawk/ArduPilot) connected via UART
- ✅ Ground control station (QGroundControl)
- ✅ Network connectivity for UDP/TCP endpoints
- ✅ Serial device access (/dev/serial0)

### Software Requirements
- ✅ k3s cluster running on Raspberry Pi
- ✅ Existing mavlink-router deployment
- ✅ ConfigMap with current configuration
- ✅ announcer-ex running for system announcements
- ✅ Access to deploy and test RouterEx container

### Configuration Requirements
- ✅ Current mavlink-router configuration (for comparison)
- ✅ Understanding of current message routing behavior
- ✅ List of expected endpoints and connections
- ✅ Performance baselines (latency, throughput)

## Phase 7 Tasks

### 7.1 Hardware Deployment (Week 7)

**Objective**: Deploy RouterEx to Raspberry Pi and verify basic functionality

**Tasks**:
1. Deploy RouterEx container to k3s cluster
   ```bash
   kubectl apply -f apps/router_ex/k8s/router-ex-deployment.yaml
   ```

2. Verify pod starts successfully
   ```bash
   kubectl get pods -n rpiuav
   kubectl logs -n rpiuav <router-ex-pod> --follow
   ```

3. Check serial device access
   ```bash
   kubectl exec -n rpiuav <router-ex-pod> -- ls -l /dev/serial0
   ```

4. Verify endpoints start
   - Check logs for endpoint initialization
   - Verify no errors during startup
   - Confirm all configured endpoints are running

5. Test basic health check
   ```bash
   kubectl exec -n rpiuav <router-ex-pod> -- bin/router_ex rpc "RouterEx.health_check()"
   ```

**Success Criteria**:
- ✅ Pod starts and remains running
- ✅ Serial device accessible with correct permissions
- ✅ All endpoints initialize successfully
- ✅ Health check returns {:ok, ...}
- ✅ No errors in logs

**Expected Issues**:
- Serial device permissions (may need privileged security context adjustment)
- ConfigMap format compatibility
- Resource limits too restrictive
- Network port conflicts

### 7.2 Side-by-Side Testing (Week 7)

**Objective**: Run RouterEx alongside mavlink-router to compare behavior

**Tasks**:
1. Configure RouterEx on different TCP port (e.g., 5761 instead of 5760)
   - Update ConfigMap with test configuration
   - Keep mavlink-router on port 5760

2. Connect both routers to same serial device (if possible) or use message replay

3. Compare message routing:
   ```bash
   # Monitor RouterEx
   kubectl exec -n rpiuav <router-ex-pod> -- bin/router_ex rpc "RouterEx.RouterCore.get_stats()"

   # Monitor mavlink-router logs
   kubectl logs -n rpiuav <mavlink-router-pod>
   ```

4. Verify identical message forwarding
   - Same messages routed to same destinations
   - Same filtering behavior
   - No message loss

5. Test with QGroundControl on test port

**Success Criteria**:
- ✅ RouterEx routes same messages as mavlink-router
- ✅ Message filtering matches expected behavior
- ✅ No messages dropped or lost
- ✅ QGC can connect to both routers
- ✅ Flight controller communication works on both

**Expected Issues**:
- Slight differences in routing logic
- Timing differences
- Filter configuration format differences
- Edge cases in MAVLink parsing

### 7.3 Performance Validation (Week 7-8)

**Objective**: Validate RouterEx meets performance requirements on Pi

**Tasks**:
1. Measure routing latency
   ```bash
   # Use telemetry events to measure message routing time
   # Target: <2ms per message
   ```

2. Measure throughput
   ```bash
   # Monitor packets/second under load
   # Target: >5000 msg/s
   ```

3. Monitor resource usage
   ```bash
   kubectl top pod -n rpiuav <router-ex-pod>
   # Target: <15% CPU idle, <150MB memory
   ```

4. Run 24-hour stability test
   - Monitor for memory leaks
   - Check for connection drops
   - Verify no crashes or restarts

5. Test connection churn
   - Rapidly connect/disconnect clients
   - Verify routing table updates correctly
   - Check for resource leaks

**Success Criteria**:
- ✅ Latency <2ms average
- ✅ Throughput >5000 msg/s sustained
- ✅ CPU usage <15% idle
- ✅ Memory usage <150MB stable
- ✅ 24 hours with no crashes
- ✅ No memory leaks detected

**Expected Issues**:
- Higher latency than development environment
- Lower throughput due to Pi hardware limits
- Memory usage higher on ARM architecture
- Need for performance tuning

### 7.4 Migration Execution (Week 8)

**Objective**: Migrate from mavlink-router to RouterEx in production

**Prerequisites**:
- ✅ All Phase 7.1-7.3 tests passing
- ✅ Migration guide created
- ✅ Rollback procedure documented
- ✅ Backup of current configuration
- ✅ Maintenance window scheduled (if needed)

**Migration Steps**:

1. **Pre-Migration Checks**
   ```bash
   # Backup current configuration
   kubectl get configmap -n rpiuav rpi4-configmap -o yaml > backup-configmap.yaml

   # Document current mavlink-router behavior
   kubectl logs -n rpiuav <mavlink-router-pod> > mavlink-router-baseline.log

   # Verify RouterEx test deployment is stable
   kubectl get pods -n rpiuav | grep router-ex
   ```

2. **Update ConfigMap**
   ```bash
   # Update rpi4-configmap with RouterEx configuration
   kubectl edit configmap -n rpiuav rpi4-configmap
   ```

3. **Scale Down mavlink-router**
   ```bash
   kubectl scale deployment mavlink-router -n rpiuav --replicas=0
   ```

4. **Deploy RouterEx to Production Port**
   ```bash
   # Update router-ex-deployment.yaml to use port 5760
   kubectl apply -f apps/router_ex/k8s/router-ex-deployment.yaml
   ```

5. **Smoke Tests**
   ```bash
   # Verify flight controller connection
   # Test QGroundControl connection
   # Check announcer-ex integration
   # Monitor for errors
   kubectl logs -n rpiuav <router-ex-pod> --follow
   ```

6. **Monitor for 1 Hour**
   - Watch logs for errors
   - Verify message routing working
   - Check all endpoints connected
   - Monitor resource usage

7. **If Successful**: Remove mavlink-router deployment
   ```bash
   kubectl delete deployment mavlink-router -n rpiuav
   ```

8. **If Issues Found**: Rollback
   ```bash
   # Scale down RouterEx
   kubectl scale deployment router-ex -n rpiuav --replicas=0

   # Restore mavlink-router
   kubectl scale deployment mavlink-router -n rpiuav --replicas=1

   # Restore ConfigMap if changed
   kubectl apply -f backup-configmap.yaml
   ```

**Success Criteria**:
- ✅ RouterEx running on production port 5760
- ✅ All endpoints connected and working
- ✅ Flight controller communication normal
- ✅ QGC can connect and control vehicle
- ✅ announcer-ex integration working
- ✅ No errors in logs after 1 hour
- ✅ mavlink-router successfully removed

**Expected Issues**:
- Configuration format incompatibilities
- Port binding conflicts
- Timing issues with announcer-ex
- Unexpected message routing differences
- Serial device access issues

### 7.5 Bug Fixes and Iteration (Week 8+)

**Objective**: Fix all issues discovered during hardware testing

**Process**:
1. Document each bug found
   - Reproduction steps
   - Expected vs actual behavior
   - Logs and error messages
   - Impact severity

2. Prioritize bugs
   - Critical: Blocks migration or causes data loss
   - High: Affects functionality but has workaround
   - Medium: Minor issues or edge cases
   - Low: Nice-to-have improvements

3. Fix bugs locally
   - Write failing test first
   - Implement fix
   - Verify test passes
   - Run full test suite

4. Deploy fix to hardware
   - Build new container image
   - Push to GHCR
   - Update k8s deployment
   - Verify fix on hardware

5. Repeat until all critical/high bugs fixed

**Success Criteria**:
- ✅ All critical bugs fixed
- ✅ All high priority bugs fixed
- ✅ Tests added for each bug
- ✅ Documentation updated with findings

### 7.6 Final Validation (Week 9)

**Objective**: Confirm RouterEx is production-ready

**Tasks**:
1. Run full test suite on hardware
2. Perform final performance validation
3. Update operations guide with hardware-specific notes
4. Create migration guide for future deployments
5. Document all issues found and resolutions
6. Get user sign-off on functionality

**Success Criteria**:
- ✅ All tests passing on hardware
- ✅ Performance meets requirements
- ✅ Documentation complete and accurate
- ✅ User confirms RouterEx works as expected
- ✅ No known critical or high priority bugs

## Expected Timeline

| Week | Phase | Tasks |
|------|-------|-------|
| 7 | 7.1-7.2 | Hardware deployment, side-by-side testing |
| 7-8 | 7.3 | Performance validation, 24h stability test |
| 8 | 7.4 | Migration execution |
| 8+ | 7.5 | Bug fixes (timeline depends on issues found) |
| 9 | 7.6 | Final validation |

**Total Estimated Time**: 2-3 weeks (assuming no major issues)

**Contingency**: Add 1-2 weeks if significant bugs are discovered

## Known Risks

### High Risk
- **Serial device access issues**: Privileged container requirements on k3s
  - *Mitigation*: Test device access before full deployment

- **Configuration incompatibility**: INI parser may not handle all edge cases
  - *Mitigation*: Validate current ConfigMap format before migration

- **Performance issues on Pi**: ARM architecture may have different characteristics
  - *Mitigation*: Performance validation before migration

### Medium Risk
- **Message routing differences**: Subtle differences from mavlink-router behavior
  - *Mitigation*: Side-by-side comparison testing

- **Integration issues with announcer-ex**: Timing or routing differences
  - *Mitigation*: Test with announcer-ex before migration

### Low Risk
- **Resource limit adjustments**: May need to tune CPU/memory limits
  - *Mitigation*: Monitor and adjust during testing

## Success Criteria for Phase 7

RouterEx can only be considered complete when:

1. ✅ **Deployed successfully** to Raspberry Pi CM4/CM5
2. ✅ **All endpoints working** (Serial, UDP, TCP)
3. ✅ **Flight controller communication** stable and reliable
4. ✅ **QGroundControl connection** working normally
5. ✅ **announcer-ex integration** functioning correctly
6. ✅ **Performance validated** on target hardware
7. ✅ **Migration completed** from mavlink-router
8. ✅ **24-hour stability test** passed
9. ✅ **All critical bugs fixed** from real-world testing
10. ✅ **Documentation updated** with hardware findings

## Deliverables

At the end of Phase 7, the following must be complete:

1. **Migration Guide** (`docs/migration.md`)
   - Step-by-step migration procedure
   - Configuration conversion instructions
   - Rollback procedures
   - Troubleshooting common migration issues

2. **Hardware Testing Report**
   - Performance benchmarks on Pi
   - Issues discovered and resolutions
   - Configuration recommendations
   - Lessons learned

3. **Updated Operations Guide**
   - Hardware-specific setup notes
   - Raspberry Pi deployment instructions
   - Troubleshooting for hardware issues
   - Performance tuning recommendations

4. **Bug Fixes**
   - All critical bugs fixed
   - Tests added for hardware-specific issues
   - Code updated and deployed

5. **Production Deployment**
   - RouterEx running in production
   - mavlink-router removed
   - Monitoring in place
   - User sign-off obtained

## Post-Phase 7

Once Phase 7 is complete:

1. **Create v1.0.0 Release**
   - Tag release in git
   - Create GitHub release with changelog
   - Document breaking changes (if any)

2. **Close PRD-004**
   - Mark as COMPLETE
   - Document final outcomes
   - Archive planning documents

3. **Monitor Production**
   - Watch for issues in first week
   - Collect feedback from users
   - Plan future enhancements

## Conclusion

Phase 7 is the **final and most critical phase** of RouterEx development. While Phases 1-6 have delivered a solid MVP, only real-world testing on target hardware can validate production readiness.

The user's expectation is correct: **"lots of errors surface during real testing"**. Phase 7 must be approached with:
- Thorough testing methodology
- Clear rollback procedures
- Iterative bug fixing
- User collaboration and feedback

**PRD-004 will remain OPEN** until all Phase 7 objectives are met and RouterEx is running successfully in production.

---

**Created**: 2025-01-24
**Status**: Planning Complete - Awaiting Hardware Access
**Blocking**: Hardware availability, user availability for testing
**Next Step**: User to initiate Phase 7 when ready with hardware access
