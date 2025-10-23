# Video Streamer Operations Guide

This guide covers deployment, configuration, monitoring, and maintenance procedures for the video streaming service.

## Table of Contents

- [Deployment](#deployment)
- [Configuration Management](#configuration-management)
- [Monitoring](#monitoring)
- [Common Operations](#common-operations)
- [Performance Tuning](#performance-tuning)
- [Troubleshooting](#troubleshooting)
- [Backup & Recovery](#backup--recovery)
- [Security](#security)

## Deployment

### Prerequisites

- Kubernetes cluster (k3s) running on Raspberry Pi
- Docker registry access (ghcr.io)
- kubectl configured with cluster access
- Raspberry Pi Camera connected (IMX477 or IMX219)

### Initial Deployment

1. **Build and push Docker image**:

```bash
# Navigate to video_streamer directory
cd apps/video_streamer

# Build for ARM64
docker build --platform linux/arm64 \
  -t ghcr.io/fancydrones/x500-cm4/video-streamer:$(date +%Y%m%d-%H%M%S) .

# Tag as latest
docker tag ghcr.io/fancydrones/x500-cm4/video-streamer:$(date +%Y%m%d-%H%M%S) \
  ghcr.io/fancydrones/x500-cm4/video-streamer:latest

# Push to registry
docker push ghcr.io/fancydrones/x500-cm4/video-streamer:$(date +%Y%m%d-%H%M%S)
docker push ghcr.io/fancydrones/x500-cm4/video-streamer:latest
```

2. **Deploy to Kubernetes**:

```bash
# Apply deployment manifest
kubectl apply -f ../../deploy/k8s/video-streamer/

# Verify deployment
kubectl get pods -l app=video-streamer

# Expected output:
# NAME                              READY   STATUS    RESTARTS   AGE
# video-streamer-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

3. **Verify service is accessible**:

```bash
# Check service
kubectl get svc video-streamer

# Test RTSP connectivity
nc -zv 10.10.10.2 8554

# Test stream with VLC
vlc rtsp://10.10.10.2:8554/video
```

### Deployment Manifest Structure

```
deploy/k8s/video-streamer/
├── deployment.yaml          # Deployment with pod spec
├── service.yaml            # Service (NodePort/ClusterIP)
├── configmap.yaml          # Configuration (optional)
└── kustomization.yaml      # Kustomize overlay (optional)
```

**Key Deployment Settings**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: video-streamer
spec:
  replicas: 1  # Single instance (camera is exclusive resource)
  selector:
    matchLabels:
      app: video-streamer
  template:
    metadata:
      labels:
        app: video-streamer
    spec:
      nodeSelector:
        # Schedule on node with camera
        camera: "true"
      containers:
      - name: video-streamer
        image: ghcr.io/fancydrones/x500-cm4/video-streamer:latest
        ports:
        - containerPort: 8554
          name: rtsp
          protocol: TCP
        env:
        - name: STREAM_WIDTH
          value: "1920"
        - name: STREAM_HEIGHT
          value: "1080"
        - name: STREAM_FPS
          value: "30"
        - name: H264_PROFILE
          value: "main"
        resources:
          requests:
            memory: "100Mi"
            cpu: "100m"
          limits:
            memory: "200Mi"
            cpu: "1000m"
        securityContext:
          privileged: true  # Required for /dev/video* access
        volumeMounts:
        - name: dev-video
          mountPath: /dev/video10
        - name: dev-video-index
          mountPath: /dev/video11
      volumes:
      - name: dev-video
        hostPath:
          path: /dev/video10
      - name: dev-video-index
        hostPath:
          path: /dev/video11
```

### GitOps Workflow

For production deployments, use GitOps with ArgoCD or Flux:

1. **Commit deployment changes** to git repository
2. **GitOps controller** detects changes
3. **Automatic sync** applies to cluster
4. **Rollback** via git revert if needed

**Example ArgoCD Application**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: video-streamer
spec:
  project: default
  source:
    repoURL: https://github.com/fancydrones/x500-cm4
    targetRevision: main
    path: deploy/k8s/video-streamer
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Rolling Updates

```bash
# Update image tag in deployment
kubectl set image deployment/video-streamer \
  video-streamer=ghcr.io/fancydrones/x500-cm4/video-streamer:20250123-120000

# Watch rollout
kubectl rollout status deployment/video-streamer

# Check rollout history
kubectl rollout history deployment/video-streamer

# Rollback if needed
kubectl rollout undo deployment/video-streamer
```

**Note**: Rolling updates will briefly interrupt streaming during pod replacement. For zero-downtime, consider blue-green deployment strategy.

## Configuration Management

### Environment-Based Configuration

Configuration is managed via environment variables in Kubernetes deployment:

**Development/Testing**:
```yaml
env:
- name: STREAM_WIDTH
  value: "1280"
- name: STREAM_HEIGHT
  value: "720"
- name: STREAM_FPS
  value: "15"
- name: H264_PROFILE
  value: "baseline"
```

**Production**:
```yaml
env:
- name: STREAM_WIDTH
  value: "1920"
- name: STREAM_HEIGHT
  value: "1080"
- name: STREAM_FPS
  value: "30"
- name: H264_PROFILE
  value: "main"
- name: H264_LEVEL
  value: "4.1"
```

### ConfigMap-Based Configuration

For better organization, use ConfigMaps:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: video-streamer-config
data:
  STREAM_WIDTH: "1920"
  STREAM_HEIGHT: "1080"
  STREAM_FPS: "30"
  H264_PROFILE: "main"
  H264_LEVEL: "4.1"
  KEYFRAME_INTERVAL: "30"
```

Reference in deployment:
```yaml
envFrom:
- configMapRef:
    name: video-streamer-config
```

### Secrets Management

For sensitive configuration (RTSP authentication):

```bash
# Create secret
kubectl create secret generic video-streamer-auth \
  --from-literal=RTSP_USERNAME=admin \
  --from-literal=RTSP_PASSWORD=secure_password
```

Reference in deployment:
```yaml
env:
- name: RTSP_AUTH
  value: "true"
- name: RTSP_USERNAME
  valueFrom:
    secretKeyRef:
      name: video-streamer-auth
      key: RTSP_USERNAME
- name: RTSP_PASSWORD
  valueFrom:
    secretKeyRef:
      name: video-streamer-auth
      key: RTSP_PASSWORD
```

### Configuration Validation

Before applying configuration changes:

```bash
# Validate YAML syntax
kubectl apply --dry-run=client -f deployment.yaml

# Validate with server-side checks
kubectl apply --dry-run=server -f deployment.yaml

# Apply and monitor
kubectl apply -f deployment.yaml && kubectl logs -f deployment/video-streamer
```

## Monitoring

### Health Checks

**Liveness Probe** (restart if unhealthy):
```yaml
livenessProbe:
  tcpSocket:
    port: 8554
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3
```

**Readiness Probe** (remove from service if not ready):
```yaml
readinessProbe:
  tcpSocket:
    port: 8554
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 2
```

### Log Monitoring

**View real-time logs**:
```bash
# Follow logs
kubectl logs -f deployment/video-streamer

# Last 100 lines
kubectl logs deployment/video-streamer --tail=100

# Logs with timestamps
kubectl logs deployment/video-streamer --timestamps

# Previous pod (after crash)
kubectl logs deployment/video-streamer --previous
```

**Log patterns to monitor**:
- ✅ `Starting VideoStreamer application` - Normal startup
- ⚠️ `Camera failed to open` - Camera issue
- ⚠️ `Max retries exceeded` - Persistent camera failure
- ✅ `Using camera binary: rpicam-vid` - Camera initialized
- ⚠️ `Pipeline crashed` - Pipeline failure (check logs for cause)
- ✅ `Client connected` - New RTSP client

### Resource Monitoring

**Pod resource usage**:
```bash
# Current usage
kubectl top pod -l app=video-streamer

# Expected output:
# NAME                              CPU(cores)   MEMORY(bytes)
# video-streamer-xxxxxxxxxx-xxxxx   250m         120Mi

# Watch continuously
watch kubectl top pod -l app=video-streamer
```

**Resource alerts**:
- CPU >80%: Consider lowering resolution/framerate
- Memory >150MB: Potential memory leak, investigate
- Frequent restarts: Check camera connection or configuration

### Performance Metrics

**Telemetry endpoints** (exposed via Telemetry module):

```bash
# If metrics endpoint is enabled (future enhancement)
curl http://10.10.10.2:9090/metrics

# Example metrics:
# video_streamer_pipeline_restarts_total 0
# video_streamer_active_clients 2
# video_streamer_frames_encoded_total 45000
# video_streamer_rtp_packets_sent_total 135000
```

### Latency Measurement

**End-to-end latency test**:

```bash
# 1. Display time on screen visible to camera
date +%H:%M:%S.%N

# 2. Note time when it appears in VLC
# Difference = glass-to-glass latency

# Target: <500ms
# Typical: 300-500ms
```

**Network latency**:
```bash
# Ping test
ping -c 10 10.10.10.2

# Expected: <10ms LAN, <50ms WiFi
```

### Kubernetes Events

```bash
# Watch events for video-streamer
kubectl get events --field-selector involvedObject.name=video-streamer-xxxxxxxxxx-xxxxx

# Common events:
# - Pulled: Successfully pulled image
# - Created: Created container
# - Started: Started container
# - Killing: Stopping container (update/restart)
# - Failed: Container failed (check logs)
```

## Common Operations

### Restarting the Service

```bash
# Restart all pods (rolling restart)
kubectl rollout restart deployment/video-streamer

# Delete pod (supervisor will recreate)
kubectl delete pod -l app=video-streamer

# Scale down and up (immediate restart)
kubectl scale deployment/video-streamer --replicas=0
kubectl scale deployment/video-streamer --replicas=1
```

### Changing Configuration

```bash
# Update ConfigMap
kubectl edit configmap video-streamer-config

# Restart to apply changes
kubectl rollout restart deployment/video-streamer

# Or update via patch
kubectl patch configmap video-streamer-config \
  -p '{"data":{"STREAM_FPS":"60"}}'
```

### Updating the Image

```bash
# Update to specific version
kubectl set image deployment/video-streamer \
  video-streamer=ghcr.io/fancydrones/x500-cm4/video-streamer:20250123

# Update to latest
kubectl set image deployment/video-streamer \
  video-streamer=ghcr.io/fancydrones/x500-cm4/video-streamer:latest

# Force pull new image
kubectl rollout restart deployment/video-streamer
```

### Port Forwarding (Testing)

```bash
# Forward RTSP port to local machine
kubectl port-forward service/video-streamer 8554:8554

# Now access from local machine
vlc rtsp://localhost:8554/video
```

### Accessing Pod Shell

```bash
# Get shell in running pod
kubectl exec -it deployment/video-streamer -- /bin/sh

# Test camera from within pod
rpicam-vid -t 5000 -o test.h264

# Check network from within pod
nc -zv 10.10.10.2 8554

# Exit shell
exit
```

### Collecting Diagnostics

```bash
# Create diagnostics bundle
mkdir video-streamer-diagnostics
cd video-streamer-diagnostics

# Collect pod info
kubectl get pod -l app=video-streamer -o yaml > pod.yaml
kubectl describe pod -l app=video-streamer > pod-describe.txt

# Collect logs
kubectl logs deployment/video-streamer --tail=500 > logs.txt
kubectl logs deployment/video-streamer --previous > logs-previous.txt

# Collect events
kubectl get events --field-selector involvedObject.name=$(kubectl get pod -l app=video-streamer -o name) > events.txt

# Collect resource usage
kubectl top pod -l app=video-streamer > resources.txt

# Collect deployment config
kubectl get deployment video-streamer -o yaml > deployment.yaml

# Create tarball
cd ..
tar czf video-streamer-diagnostics.tar.gz video-streamer-diagnostics/
```

## Performance Tuning

### Resolution vs Latency

| Resolution | FPS | Latency | CPU Usage | Bandwidth |
|------------|-----|---------|-----------|-----------|
| 640x480    | 30  | ~200ms  | Low       | 1-2 Mbps  |
| 1280x720   | 30  | ~300ms  | Medium    | 2-4 Mbps  |
| 1920x1080  | 30  | ~400ms  | High      | 4-8 Mbps  |
| 1920x1080  | 60  | ~350ms  | Very High | 8-12 Mbps |

### CPU Optimization

**If CPU usage is high (>80%)**:

1. Lower resolution: `STREAM_WIDTH=1280 STREAM_HEIGHT=720`
2. Reduce framerate: `STREAM_FPS=15`
3. Increase keyframe interval: `KEYFRAME_INTERVAL=60`
4. Check for other processes consuming CPU

**Resource limits**:
```yaml
resources:
  requests:
    cpu: "500m"      # Reserve 0.5 CPU
  limits:
    cpu: "1500m"     # Max 1.5 CPU
```

### Memory Optimization

**If memory usage is high (>150MB)**:

1. Check for memory leaks (restart and monitor)
2. Reduce number of clients (each client = ~5MB overhead)
3. Adjust resource limits:

```yaml
resources:
  limits:
    memory: "200Mi"  # Kill if exceeds 200MB
```

### Network Optimization

**For bandwidth-constrained networks**:

1. Lower resolution: `STREAM_WIDTH=1280`
2. Use main/high profile: `H264_PROFILE=main`
3. Increase keyframe interval: `KEYFRAME_INTERVAL=60`
4. Monitor bandwidth usage:

```bash
# Measure bandwidth (on client)
iperf3 -c 10.10.10.2 -t 30

# Monitor network usage
kubectl top pod -l app=video-streamer --containers
```

### Latency Optimization

**For lowest latency (<300ms)**:

```yaml
env:
- name: STREAM_WIDTH
  value: "1280"
- name: STREAM_HEIGHT
  value: "720"
- name: STREAM_FPS
  value: "30"
- name: H264_PROFILE
  value: "baseline"
- name: KEYFRAME_INTERVAL
  value: "15"
```

**Client-side tuning** (VLC):
```bash
vlc --network-caching=50 --rtsp-tcp rtsp://10.10.10.2:8554/video
```

## Troubleshooting

### Service Won't Start

**Symptoms**: Pod in CrashLoopBackOff

**Diagnosis**:
```bash
# Check pod status
kubectl get pod -l app=video-streamer

# View logs
kubectl logs deployment/video-streamer

# Check events
kubectl describe pod -l app=video-streamer
```

**Common causes**:
1. **Camera not accessible**: Check device mounts in deployment
2. **Image pull failure**: Verify image exists in registry
3. **Configuration error**: Check environment variables
4. **Resource limits**: Check if OOMKilled (out of memory)

### No Video Stream

**Symptoms**: Client can't connect to RTSP server

**Diagnosis**:
```bash
# 1. Check pod is running
kubectl get pod -l app=video-streamer

# 2. Check service
kubectl get svc video-streamer

# 3. Test connectivity
nc -zv 10.10.10.2 8554

# 4. Check firewall
# (on Raspberry Pi)
sudo iptables -L -n | grep 8554
```

**Solutions**:
- Ensure service type is NodePort or LoadBalancer
- Verify network policies allow traffic
- Check firewall rules on host

### Pipeline Keeps Restarting

**Symptoms**: Frequent pod restarts, "pipeline crashed" in logs

**Diagnosis**:
```bash
# Check restart count
kubectl get pod -l app=video-streamer

# View crash logs
kubectl logs deployment/video-streamer --previous

# Check resource usage before crash
kubectl describe pod -l app=video-streamer
```

**Common causes**:
1. **Camera disconnection**: Check CSI cable
2. **Resource exhaustion**: Increase limits
3. **Configuration error**: Invalid resolution/framerate
4. **Hardware failure**: Test camera with `rpicam-vid`

### High Latency

**Symptoms**: Video delay >500ms

**Solutions**:
1. Reduce keyframe interval
2. Use baseline profile
3. Lower resolution
4. Check network latency
5. Use wired Ethernet instead of WiFi

See [Performance Tuning](#performance-tuning) for detailed optimization.

## Backup & Recovery

### Configuration Backup

```bash
# Export all video-streamer resources
kubectl get deployment,service,configmap,secret \
  -l app=video-streamer \
  -o yaml > video-streamer-backup.yaml

# Store in version control
git add video-streamer-backup.yaml
git commit -m "Backup video-streamer configuration"
git push
```

### Disaster Recovery

**Scenario: Complete cluster failure**

1. **Restore Kubernetes cluster** (k3s)
2. **Restore deployment manifests** from git
3. **Apply manifests**:

```bash
kubectl apply -f deploy/k8s/video-streamer/
```

4. **Verify deployment**:

```bash
kubectl get pods -l app=video-streamer
vlc rtsp://10.10.10.2:8554/video
```

**Recovery Time Objective (RTO)**: <5 minutes
**Recovery Point Objective (RPO)**: 0 (stateless service)

### Rollback Procedures

**Rollback deployment**:
```bash
# View rollout history
kubectl rollout history deployment/video-streamer

# Rollback to previous version
kubectl rollout undo deployment/video-streamer

# Rollback to specific revision
kubectl rollout undo deployment/video-streamer --to-revision=2

# Verify rollback
kubectl rollout status deployment/video-streamer
```

**Rollback configuration**:
```bash
# Restore from git
git checkout HEAD~1 -- deploy/k8s/video-streamer/

# Apply old configuration
kubectl apply -f deploy/k8s/video-streamer/

# Restart deployment
kubectl rollout restart deployment/video-streamer
```

## Security

### Camera Access Control

The service requires privileged access for camera hardware:

```yaml
securityContext:
  privileged: true
```

**Best practices**:
- Limit to specific device files (not full privileged mode)
- Use device plugins for controlled access (future enhancement)

### RTSP Authentication

Enable authentication to prevent unauthorized access:

```yaml
env:
- name: RTSP_AUTH
  value: "true"
- name: RTSP_USERNAME
  valueFrom:
    secretKeyRef:
      name: video-streamer-auth
      key: username
- name: RTSP_PASSWORD
  valueFrom:
    secretKeyRef:
      name: video-streamer-auth
      key: password
```

**Create secret**:
```bash
kubectl create secret generic video-streamer-auth \
  --from-literal=username=admin \
  --from-literal=password=$(openssl rand -base64 32)
```

**Note**: RTSP basic auth sends credentials in base64 (not encrypted). For production, use:
- VPN tunnel
- HTTPS reverse proxy
- Network segmentation

### Network Policies

Restrict network access to video-streamer:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: video-streamer-netpol
spec:
  podSelector:
    matchLabels:
      app: video-streamer
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 10.0.0.0/8  # Allow only internal network
    ports:
    - protocol: TCP
      port: 8554
```

### Image Security

**Scan images for vulnerabilities**:
```bash
# Using Trivy
trivy image ghcr.io/fancydrones/x500-cm4/video-streamer:latest

# Using Grype
grype ghcr.io/fancydrones/x500-cm4/video-streamer:latest
```

**Registry authentication**:
```bash
# Create image pull secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<username> \
  --docker-password=<token>

# Reference in deployment
spec:
  imagePullSecrets:
  - name: ghcr-secret
```

### Audit Logging

Enable audit logging for compliance:

```bash
# View audit logs (if enabled on k3s)
kubectl logs -n kube-system kube-apiserver-* | grep video-streamer
```

**Events to monitor**:
- Deployment updates
- Configuration changes
- Pod restarts
- Failed authentication attempts (if auth enabled)

---

For architecture details, see [architecture.md](architecture.md).
For development procedures, see [development.md](development.md).
