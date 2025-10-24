# Purpose

This is a MAVLink message router written in Elixir. Router-Ex is a companion application for the FancyDrones X500 CM4 drone controller hardware. It intelligently routes MAVLink messages between serial, UDP, and TCP connections, providing a native Elixir alternative to the C/C++ mavlink-router.

Key features include:
- MAVLink protocol support (1.0 and 2.0)
- Multiple connection types: Serial (UART), UDP (server/client), TCP (server/client)
- Intelligent routing with system awareness-based message routing
- Message filtering with whitelist/blacklist support per endpoint
- Flexible configuration supporting Elixir-native, YAML, TOML, and INI formats
- Hot code reloading capabilities
- OTP supervision for automatic fault recovery
- Rich telemetry and monitoring

## Project Guidelines

### Elixir & OTP Guidelines

- This is an **OTP application** with a supervision tree. The supervision tree order matters:
  - Dependencies must start before dependents
  - `Endpoint.Supervisor` must start before `ConfigManager` since ConfigManager starts endpoints
  - See `lib/router_ex/application.ex` for the current supervision tree order

- **XMAVLink Library Dependency**:
  - Router-Ex depends on the `xmavlink` library for MAVLink protocol support
  - XMAVLink **requires** dialect configuration in `config/*.exs` files
  - All environment configs (dev, test, prod) must include XMAVLink configuration:
    ```elixir
    config :xmavlink,
      dialect: Common,
      system_id: 255,
      component_id: 1,
      heartbeat_interval_ms: 1000
    ```

- **Testing**:
  - Run tests with `mix test`
  - Check coverage with `mix test --cover`
  - Run specific test file with `mix test test/path/to/test.exs`
  - Run failed tests with `mix test --failed`

- **Code Quality**:
  - Format code with `mix format`
  - Compile with `mix compile`
  - Generate documentation with `mix docs`

- **Configuration Management**:
  - Router-Ex supports multiple configuration formats (Elixir, INI, YAML, TOML)
  - INI format is for backward compatibility with mavlink-router
  - The `ConfigManager` module handles parsing and loading configuration
  - In production, configuration is typically loaded from the `ROUTER_CONFIG` environment variable

- **Endpoint Management**:
  - Endpoints are managed by `Endpoint.Supervisor` (a DynamicSupervisor)
  - Each endpoint type has its own GenServer implementation:
    - `Endpoint.Serial` - Serial/UART connections
    - `Endpoint.UdpServer` - UDP server listening for incoming messages
    - `Endpoint.UdpClient` - UDP client sending to specific address
    - `Endpoint.TcpServer` - TCP server accepting connections
    - `Endpoint.TcpClient` - TCP client connecting to specific address
  - Endpoints can crash and restart independently without affecting other endpoints

### Common Patterns

- **Message Routing**:
  - Messages are routed through `RouterCore` GenServer
  - Routing decisions are based on system awareness and message filtering rules
  - Each endpoint can have allow lists (whitelist) or block lists (blacklist) for message IDs

- **Telemetry**:
  - The application uses Elixir's telemetry library extensively
  - Telemetry events track message routing, endpoint connections, and performance metrics
  - See `lib/router_ex/telemetry.ex` for event definitions

- **Error Handling**:
  - Use supervision trees for fault tolerance
  - Let processes crash and restart rather than defensive programming
  - Log errors appropriately with Logger module

## Deployment Procedure

All changes to Router-Ex should follow this deployment workflow:

### 1. Create a New Branch

Always work in a new branch based on the latest version of `main`:

```bash
# Make sure you're on main and it's up to date
git checkout main
git pull origin main

# Create a new feature branch
git checkout -b fix-description-of-issue
# or
git checkout -b feature-description
```

### 2. Make Your Changes

- Make the necessary code changes
- Run tests to ensure everything works: `mix test`
- Format code: `mix format`
- Update documentation if needed

### 3. Commit Changes

```bash
# Stage your changes
git add path/to/changed/files

# Commit with a descriptive message
git commit -m "Description of changes

More detailed explanation if needed.

Fixes: Issue description or reference
"
```

### 4. Push to Remote

```bash
# Push your branch to the remote repository
git push -u origin your-branch-name
```

### 5. Create a Pull Request

- Go to GitHub and create a Pull Request (PR) from your branch to `main`
- The PR will automatically trigger CI checks:
  - `.github/workflows/pr-router-ex.yaml` - Runs tests and validation
  - GitHub Actions will build and validate your changes

### 6. Wait for CI Checks

- Monitor the PR checks to ensure all tests pass
- Fix any issues that arise during CI validation
- Push additional commits to your branch if needed (they will automatically update the PR)

### 7. Merge to Main

- Once all checks pass and the PR is reviewed (if applicable), merge to `main`
- This can be done via the GitHub UI

### 8. Automatic Deployment

When your PR is merged to `main`:

1. **GitHub Actions Build** (`.github/workflows/process-router-ex.yaml`):
   - Automatically triggered on push to `main` with changes to `apps/router_ex/**`
   - Builds a new Docker image for ARM64 architecture
   - Tags the image with date and commit hash (e.g., `20251024-be53eca`)
   - Pushes to GitHub Container Registry: `ghcr.io/fancydrones/x500-cm4/router-ex`

2. **Deployment Update**:
   - GitHub Actions automatically updates `deployments/apps/router-ex-deployment.yaml`
   - Commits the new image tag back to the repository
   - This triggers the GitOps workflow

3. **Flux Pulls New Version**:
   - Flux (running on the CM4) monitors the repository
   - Detects the updated deployment manifest
   - Pulls the new router-ex image from GHCR
   - Applies the updated deployment to the Kubernetes cluster
   - Router-Ex pod restarts with the new version

### Manual Deployment Trigger

You can also manually trigger a deployment workflow:

1. Go to GitHub Actions
2. Select "Router-Ex image" workflow
3. Click "Run workflow"
4. Select the `main` branch
5. Click "Run workflow" button

### Monitoring Deployment

After merging to main, you can monitor the deployment:

```bash
# Watch the GitHub Actions build
# (Check the Actions tab on GitHub)

# Once deployed, check pod status on hardware
kubectl get pods -n rpiuav -w

# Check logs for the new pod
kubectl logs -n rpiuav -l app=router-ex-replicaset --follow

# Verify the new image version
kubectl get deployment router-ex -n rpiuav -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Rollback Procedure

If issues are found after deployment:

1. **Quick Rollback via Git**:
   ```bash
   # Revert the merge commit on main
   git checkout main
   git pull
   git revert <merge-commit-hash>
   git push
   ```
   This will trigger a new build with the previous version.

2. **Manual Rollback on Hardware**:
   ```bash
   # Scale down current deployment
   kubectl scale deployment router-ex -n rpiuav --replicas=0

   # Update deployment to previous image version
   kubectl set image deployment/router-ex router-ex=ghcr.io/fancydrones/x500-cm4/router-ex:<previous-tag> -n rpiuav

   # Scale back up
   kubectl scale deployment router-ex -n rpiuav --replicas=1
   ```

## Configuration in Production

Router-Ex configuration on the CM4 is managed via Kubernetes ConfigMap:

- ConfigMap name: `rpi4-config` (in namespace `rpiuav`)
- Configuration key: `ROUTER_CONFIG`
- Format: INI (for backward compatibility with mavlink-router)

To view current configuration:
```bash
kubectl get configmap rpi4-config -n rpiuav -o yaml
```

To update configuration:
```bash
kubectl edit configmap rpi4-config -n rpiuav
# Edit the ROUTER_CONFIG section
# Save and exit

# Restart router-ex to pick up changes
kubectl rollout restart deployment/router-ex -n rpiuav
```

## Troubleshooting

### Common Issues

1. **Pod in CrashLoopBackOff**:
   - Check logs: `kubectl logs -n rpiuav <pod-name>`
   - Common causes:
     - Missing XMAVLink dialect configuration
     - Supervisor ordering issues
     - Serial device access issues
     - Invalid configuration in ConfigMap

2. **Serial Device Access Issues**:
   - Router-Ex requires privileged access to `/dev/serial0`
   - Check deployment has `privileged: true` in securityContext
   - Verify device exists on host: `kubectl exec -n rpiuav <pod> -- ls -l /dev/serial0`

3. **Configuration Parse Errors**:
   - Validate INI syntax in ConfigMap
   - Check logs for parsing errors
   - Compare with working configuration examples in PRDs

4. **Endpoint Connection Failures**:
   - Check endpoint configuration (port, address, device)
   - Verify network connectivity for UDP/TCP endpoints
   - Check firewall rules if using TCP server

## Related Documentation

- [PRD-004](../../PRDs/004-router-ex/README.md) - Complete implementation plan
- [Phase 7 Hardware Testing Plan](../../PRDs/004-router-ex/phase7-hardware-testing-plan.md) - Hardware deployment guide
- [Configuration Formats](../../PRDs/004-router-ex/configuration-formats.md) - Configuration reference
- [Testing Guide](../../PRDs/004-router-ex/testing-guide.md) - Testing strategy
- [Operations Guide](docs/operations.md) - Operational procedures
