In summary, the report provides a step-by-step guide on how cameras should announce themselves in MAVLink v2.0. It explains that a camera must broadcast heartbeats with a unique component ID and respond to MAV_CMD_REQUEST_MESSAGE with detailed CAMERA_INFORMATION, specifying its capabilities via CAMERA_CAP_FLAGS such as video capture, still images, zoom and focus control. The document clarifies the importance of proper flag settings and camera modes for ensuring automatic detection and integration with ground control software like QGroundControl.

The report further outlines how to advertise streaming capabilities using VIDEO_STREAM_INFORMATION messages, describing fields like stream type, URI, and video stream status flags. It also covers pan/tilt announcements through the gimbal protocol by detailing GIMBAL_DEVICE_INFORMATION and relevant capability flags, enabling ground stations to offer appropriate gimbal controls. Implementation notes for Elixir using the xmavlink library are included, offering illustrative code for sending heartbeats and handling message requests. Collectively, these guidelines ensure a camera can be seamlessly discovered and controlled in a MAVLink ecosystem.
# Announcing a Camera, Video Streaming, and Pan/Tilt (Gimbal) over **MAVLink 2.0** — What QGroundControl Expects

> **Goal**: Make your camera show up automatically in **QGroundControl (QGC)** with working video preview and (optional) pan/tilt controls by advertising capabilities using the **MAVLink 2.0 Camera Protocol v2** and **Gimbal Protocol v2**.  
> **Priority**: Message flow and message/enum details (protocol) rather than implementation. Examples assume you’ll implement with **Elixir** and **xmavlink**, but the wire protocol is platform-agnostic.

---

## TL;DR — Minimum for Auto‑Discovery in QGC

1. **Identify as a camera component**  
   Send `HEARTBEAT` with `type=MAV_TYPE_CAMERA` and a camera component id (`MAV_COMP_ID_CAMERA`, `MAV_COMP_ID_CAMERA2`, …). QGC watches for heartbeats to discover components.  
   Sources: [MAVLink Heartbeat](https://mavlink.io/en/messages/common.html#HEARTBEAT), [ID assignment](https://mavlink.io/en/services/mavlink_id_assignment.html)

2. **Answer `CAMERA_INFORMATION (259)`** on request (and you may also emit once on startup).  
   Populate `flags` with `CAMERA_CAP_FLAGS_HAS_VIDEO_STREAM` (and any other supported bits), and set `cam_definition_uri` (optional but recommended).  
   Sources: [Camera Protocol v2 — Discovery](https://mavlink.io/en/services/camera_v2.html#camera-identification-and-details), [CAMERA_INFORMATION (259)](https://mavlink.io/en/messages/common.html#CAMERA_INFORMATION)

3. **Advertise streams** when QGC asks:  
   QGC typically sends `MAV_CMD_REQUEST_MESSAGE` for `VIDEO_STREAM_INFORMATION (269)`. Respond with one `VIDEO_STREAM_INFORMATION` **per stream** (set `count` to total streams, `stream_id` starting at 1, `type`, `name`, `uri`, `encoding`).  
   Sources: [Camera v2 — Video stream discovery & control](https://mavlink.io/en/services/camera_v2.html#video-stream-discovery-and-control), [VIDEO_STREAM_INFORMATION (269)](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_INFORMATION), [VIDEO_STREAM_TYPE enum](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_TYPE)

4. **Publish stream status**:  
   On request (and then at a low rate), send `VIDEO_STREAM_STATUS (270)` with `flags`, `framerate`, `resolution_h/v`, etc.  
   Sources: [VIDEO_STREAM_STATUS (270)](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_STATUS)

5. **(Optional) Pan/Tilt** via **Gimbal Protocol v2**:  
   Answer `GIMBAL_MANAGER_INFORMATION (280)` (and send `GIMBAL_MANAGER_STATUS (281)` at ~5 Hz). Support `GIMBAL_MANAGER_SET_ATTITUDE (282)` to accept attitude setpoints from QGC.  
   Sources: [Gimbal Protocol v2](https://mavlink.io/en/services/gimbal_v2.html)

If you do those five things, **QGC will list your camera and show the video automatically** (assuming the URI is reachable and the encoding is supported).  
Source: [mavlink-camera-manager README (“video should automatically popup”)](https://github.com/mavlink/mavlink-camera-manager#receiving-a-stream-from-a-mavlink-ground-control-station-like-qgroundcontrol)

---

## Addressing & Discovery

### System/Component IDs and Types
- **System ID (`sysid`)**: Unique per vehicle/system on the network.  
- **Component ID (`compid`)**: Unique per component within a system. Use camera IDs from `MAV_COMPONENT`: `MAV_COMP_ID_CAMERA`, `MAV_COMP_ID_CAMERA2`, … for multiple cameras.  
- **Type**: In `HEARTBEAT.type` set `MAV_TYPE_CAMERA` for camera, `MAV_TYPE_GIMBAL` for gimbal. QGC determines component type from `HEARTBEAT.type`, *not* from compid alone.  
Sources: [ID assignment](https://mavlink.io/en/services/mavlink_id_assignment.html), [HEARTBEAT](https://mavlink.io/en/messages/common.html#HEARTBEAT)

### Standalone Camera vs. Autopilot‑Attached
- **Standalone MAVLink camera component**:  
  Your camera process sends its own `HEARTBEAT` (`type=MAV_TYPE_CAMERA`) and implements the camera microservice.  
- **Autopilot‑attached (proxied) camera**:  
  Autopilot returns multiple `CAMERA_INFORMATION` messages (each with a unique `camera_device_id` 1..6). Even if proxied, QGC interacts via the same messages.  
Source: [Camera v2 — “How cameras are attached to MAVLink networks”](https://mavlink.io/en/services/camera_v2.html#how-cameras-are-attached-to-mavlink-networks)

---

## Camera Announcement (Protocol v2)

### 1) HEARTBEAT (Message ID 0)
- **Who sends**: Camera (and gimbal).  
- **Key fields**:  
  - `type = MAV_TYPE_CAMERA`  
  - `autopilot = MAV_AUTOPILOT_INVALID` (for non‑FC components)  
- **Why**: Lets QGC detect a camera component and then request details.  
Source: [HEARTBEAT](https://mavlink.io/en/messages/common.html#HEARTBEAT)

### 2) CAMERA_INFORMATION (Message ID **259**) — *Identification & Capabilities*
- **How it starts**: QGC sends `MAV_CMD_REQUEST_MESSAGE` with `param1=259` to your camera.  
- **You reply**: A single `CAMERA_INFORMATION` with (most important fields):  
  - `vendor_name`, `model_name` (human‑readable)  
  - `firmware_version` (packed)  
  - `resolution_h`, `resolution_v` (if known)  
  - `flags: CAMERA_CAP_FLAGS` — **set `HAS_VIDEO_STREAM`** if you will advertise streams; include any other supported bits (e.g., `CAPTURE_IMAGE`, `CAPTURE_VIDEO`, `HAS_TRACKING_POINT`, `HAS_TRACKING_RECTANGLE`).  
  - `cam_definition_version`, `cam_definition_uri` — **recommended**. URI may be `http://…` or `mavlinkftp://…` and can be `.xml.xz` compressed; QGC will fetch and parse to build UI.  
  - `gimbal_device_id` — compid of an associated gimbal (or 1..6 for non‑MAVLink gimbals), 0 if none.  
  - `camera_device_id` — 1..6 if this is an autopilot‑attached camera; 0 for standalone.  
- **Why**: This is the minimum for QGC to know what your camera can do.  
Sources: [Camera v2 — discovery & details](https://mavlink.io/en/services/camera_v2.html#camera-identification-and-details), [CAMERA_INFORMATION (259)](https://mavlink.io/en/messages/common.html#CAMERA_INFORMATION), [Camera Definition File](https://mavlink.io/en/services/camera_def.html)

> **Tip**: Even if QGC doesn’t request immediately, you can emit `CAMERA_INFORMATION` once on startup (not required by spec) — it helps some tools and simplifies debugging.

### 3) (Optional but common) CAMERA_SETTINGS / STORAGE_INFORMATION / CAMERA_CAPTURE_STATUS
These round out the UI when QGC queries them, but they are **not required** just to get your stream to appear.  
Source: [Camera v2 — overview of messages](https://mavlink.io/en/services/camera_v2.html)

---

## Advertising **Video Streaming**

### A. Declare that you have streams
In `CAMERA_INFORMATION.flags` set `CAMERA_CAP_FLAGS_HAS_VIDEO_STREAM`.  
Source: [Camera v2 — stream discovery](https://mavlink.io/en/services/camera_v2.html#video-stream-discovery-and-control)

### B. Answer stream discovery
QGC typically sends:  
- `MAV_CMD_REQUEST_MESSAGE` for **`VIDEO_STREAM_INFORMATION (269)`** (sometimes for a specific `stream_id`, often `0`/all).  
You must respond with **one `VIDEO_STREAM_INFORMATION` per available stream**. Set:
- `stream_id`: **1‑based** index (1, 2, …).  
- `count`: total number of streams.  
- `type`: `VIDEO_STREAM_TYPE` (see enum below).  
- `name[32]`: short label (“Main”, “Thermal”, …).  
- `uri[160]`: the connection string; rules are per `type` (see examples).  
- `encoding`: `VIDEO_STREAM_ENCODING` (e.g., H.264, H.265, MJPEG — value per enum).  
Sources: [VIDEO_STREAM_INFORMATION (269)](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_INFORMATION), [Camera v2 — request/response](https://mavlink.io/en/services/camera_v2.html#video-stream-discovery-and-control)

**`VIDEO_STREAM_TYPE` (selected values)**  
- `VIDEO_STREAM_TYPE_RTSP (0)`: RTSP URI, e.g., `rtsp://192.168.0.10:8554/main`  
- `VIDEO_STREAM_TYPE_RTPUDP (1)`: RTP over UDP; **URI gives the UDP port** the GCS should listen to (e.g., `5600`) or a URI string acceptable to QGC.  
- `VIDEO_STREAM_TYPE_TCP_MPEG (2)`: MPEG over TCP (URI is TCP endpoint).  
- `VIDEO_STREAM_TYPE_MPEG_TS (3)`: MPEG‑TS; **URI gives the port**.  
Source: [VIDEO_STREAM_TYPE enum](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_TYPE)

> **QGC URI examples**  
> - **RTSP**: `rtsp://<ip>:8554/stream`  
> - **UDP/RTP**: a port value like `5600` (per spec), or a URI QGC understands (many implementations use `udp://0.0.0.0:5600`).  
> - **TCP**: `tcp://<ip>:<port>`  
> Ensure your URI matches what your streaming server actually exposes.

### C. Report stream status
QGC may request **`VIDEO_STREAM_STATUS (270)`** (and may expect you to update it at a low rate while streaming):
- `flags: VIDEO_STREAM_STATUS_FLAGS` — include `RUNNING` when active.  
- `framerate` (Hz), `resolution_h/v` (pixels), `bitrate` (bits/s), `rotation` (deg clockwise), `hfov` (deg).  
Source: [VIDEO_STREAM_STATUS (270)](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_STATUS)

### D. Start/Stop streaming (optional/rare for RTSP/TCP)
- `MAV_CMD_VIDEO_START_STREAMING (2502)` / `MAV_CMD_VIDEO_STOP_STREAMING (2503)` target a `stream_id`. These are mostly for **push** protocols; for RTSP/TCP the GCS connects and you may **ACK but ignore** (per spec).  
Sources: [Camera v2 — start/stop streaming semantics](https://mavlink.io/en/services/camera_v2.html#video-stream-discovery-and-control), command refs: [START/STOP STREAMING](https://hamishwillee.gitbooks.io/ham_mavdevguide/en/messages/common.html#mav_cmd_video_start_streaming)

> **What QGC actually does**: When it receives valid `VIDEO_STREAM_INFORMATION`, **video appears automatically** in the UI if the URI is reachable and encoding supported.  
> Source: [mavlink-camera-manager README](https://github.com/mavlink/mavlink-camera-manager#receiving-a-stream-from-a-mavlink-ground-control-station-like-qgroundcontrol), [QGC “Video” user guide](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/fly_view/video.html)

---

## Announcing **Pan/Tilt** (Gimbal v2)

Implement **Gimbal Protocol v2** on either your camera component or a separate gimbal component. QGC discovers manager(s) and will expose UI/controls accordingly.

### Discovery & Capabilities
- QGC checks the component’s capabilities and then requests **`GIMBAL_MANAGER_INFORMATION (280)`** via `MAV_CMD_REQUEST_MESSAGE`.  
- You respond with `GIMBAL_MANAGER_INFORMATION` specifying:  
  - `gimbal_device_id` (1:1 mapping manager↔device),  
  - capability flags `GIMBAL_MANAGER_CAP_FLAGS` (e.g., accepts Euler/Quaternion setpoints, yaw‑lock, rate control),  
  - angle/rate limits.  
- Send `GIMBAL_MANAGER_STATUS (281)` periodically (e.g., **5 Hz** recommended).  
Sources: [Gimbal v2 discovery & concepts](https://mavlink.io/en/services/gimbal_v2.html#discovery-of-gimbal-manager), [GIMBAL_MANAGER_INFORMATION (280)](https://mavlink.io/en/messages/common.html#GIMBAL_MANAGER_INFORMATION), [GIMBAL_MANAGER_STATUS (281)](https://mavlink.io/en/messages/common.html#GIMBAL_MANAGER_STATUS)

### Control API (what QGC can send)
- **`GIMBAL_MANAGER_SET_ATTITUDE (282)`**: desired camera frame attitude (quaternion/Euler/yaw rate); supports flags like yaw lock/follow.  
- The actual device broadcasts `GIMBAL_DEVICE_ATTITUDE_STATUS (285)` so UIs show the current angles.  
Sources: [GIMBAL_MANAGER_SET_ATTITUDE (282)](https://mavlink.io/en/messages/common.html#GIMBAL_MANAGER_SET_ATTITUDE), [GIMBAL_DEVICE_ATTITUDE_STATUS (285)](https://mavlink.io/en/messages/common.html#GIMBAL_DEVICE_ATTITUDE_STATUS)

> **Where to put the manager**: In simple setups, the **autopilot** plays the role of gimbal manager. For standalone integrated camera/gimbals, the **camera component** can host the manager instead (still 1:1 with its device).  
> Source: [Gimbal v2 — Common set‑ups](https://mavlink.io/en/services/gimbal_v2.html#common-set-ups)

---

## Request/Response Patterns QGC Uses

QGC (and other GCS) relies heavily on `MAV_CMD_REQUEST_MESSAGE` to **pull** state on connect or when needed.

| Purpose | Command | `param1` (message id) | Your reply |
|---|---|---:|---|
| Identify camera | `MAV_CMD_REQUEST_MESSAGE` | **259** | `CAMERA_INFORMATION` |
| Get streams | `MAV_CMD_REQUEST_MESSAGE` | **269** | `VIDEO_STREAM_INFORMATION` (one per stream) |
| Get stream status | `MAV_CMD_REQUEST_MESSAGE` | **270** | `VIDEO_STREAM_STATUS` (then continue at low rate) |
| Discover gimbals | `MAV_CMD_REQUEST_MESSAGE` | **280** | `GIMBAL_MANAGER_INFORMATION` |

Sources: [Camera v2](https://mavlink.io/en/services/camera_v2.html#message-intervals-and-requests), [Gimbal v2 discovery](https://mavlink.io/en/services/gimbal_v2.html#discovery-of-gimbal-manager)

---

## Example: One RTSP and One UDP Stream

**Assumptions**:  
- Camera component at `sysid=1`, `compid=MAV_COMP_ID_CAMERA`, `type=MAV_TYPE_CAMERA`.  
- Two streams: **Main** (RTSP/H.264) and **Thermal** (RTP/UDP/H.264).

**CAMERA_INFORMATION (259)** (key fields)
- `vendor_name="Acme"`; `model_name="DualCam-X"`  
- `flags = CAMERA_CAP_FLAGS_HAS_VIDEO_STREAM | CAMERA_CAP_FLAGS_CAPTURE_IMAGE | CAMERA_CAP_FLAGS_CAPTURE_VIDEO`  
- `cam_definition_uri="http://192.168.0.10/camera_def.xml.xz"`  

**VIDEO_STREAM_INFORMATION (269)** — send **two** messages:
1. `stream_id=1`, `count=2`, `type=VIDEO_STREAM_TYPE_RTSP (0)`, `name="Main"`,  
   `uri="rtsp://192.168.0.10:8554/main"`, `encoding=H264`  
2. `stream_id=2`, `count=2`, `type=VIDEO_STREAM_TYPE_RTPUDP (1)`, `name="Thermal"`,  
   `uri="5600"` (per spec: UDP port), `encoding=H264`

**VIDEO_STREAM_STATUS (270)** — periodic while active (example for stream 1):  
`flags=RUNNING`, `framerate=30.0`, `resolution_h=1920`, `resolution_v=1080`, `bitrate=6000000`, `rotation=0`, `hfov=90`

Sources: [VIDEO_STREAM_INFORMATION](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_INFORMATION), [VIDEO_STREAM_STATUS](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_STATUS), [VIDEO_STREAM_TYPE](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_TYPE)

---

## Pan/Tilt Only? Minimal Gimbal v2 Advertising

If your “gimbal” is just a pan/tilt head:
- Implement **Gimbal Manager v2** on the camera component.  
- On request, send `GIMBAL_MANAGER_INFORMATION (280)` with realistic yaw/pitch ranges and supported flags; send `GIMBAL_MANAGER_STATUS (281)` periodically.  
- Accept `GIMBAL_MANAGER_SET_ATTITUDE (282)` for Euler or quaternion targets.  
Source: [Gimbal v2](https://mavlink.io/en/services/gimbal_v2.html)

> **Legacy fallback**: Older stacks used `MAV_CMD_DO_MOUNT_CONTROL` and `MOUNT_STATUS` (Gimbal v1 / dialects). Prefer v2 in new designs; only add v1 if you must interop with old systems.

---

## Camera Definition File (Strongly Recommended)

Provide `cam_definition_uri` in `CAMERA_INFORMATION` so QGC can build UI controls (exposure, white balance, video mode, etc.) from your file. The file may be served via HTTP or MAVLink FTP and can be **`.xml.xz`**.  
Sources: [Camera Definition File](https://mavlink.io/en/services/camera_def.html), [Camera v2 — Additional Camera Information](https://mavlink.io/en/services/camera_v2.html#additional-camera-information)

Key notes:
- Include **`CAM_MODE`** parameter (maps to `MAV_CMD_SET_CAMERA_MODE`) so QGC can switch between photo/video settings contexts.  
- Use `PARAM_EXT_*` messages to set/get parameters defined in the file.  
Sources: [Camera Definition — schema & common parameters](https://mavlink.io/en/services/camera_def.html#schema), [Parameter protocol](https://mavlink.io/en/services/parameter.html)

---

## Message/Enum IDs You’ll Use Most

> Numbers shown here are from `common.xml` (MAVLink **common** dialect).

**Core**  
- `HEARTBEAT (0)` — discovery (set `type=MAV_TYPE_CAMERA`)  
  Source: <https://mavlink.io/en/messages/common.html#HEARTBEAT>

**Camera v2**  
- `CAMERA_INFORMATION (259)` — identification & capabilities  
  Source: <https://mavlink.io/en/messages/common.html#CAMERA_INFORMATION>  
- `VIDEO_STREAM_INFORMATION (269)` — stream descriptors  
  Source: <https://mavlink.io/en/messages/common.html#VIDEO_STREAM_INFORMATION>  
- `VIDEO_STREAM_STATUS (270)` — stream runtime status  
  Source: <https://mavlink.io/en/messages/common.html#VIDEO_STREAM_STATUS>  
- `VIDEO_STREAM_TYPE` — `RTSP(0)`, `RTPUDP(1)`, `TCP_MPEG(2)`, `MPEG_TS(3)`  
  Source: <https://mavlink.io/en/messages/common.html#VIDEO_STREAM_TYPE>  
- `CAMERA_CAP_FLAGS` — capability bits (including `HAS_VIDEO_STREAM`)  
  Source: <https://mavlink.io/en/messages/common.html#CAMERA_INFORMATION> (see “flags”/enum links)  
- `MAV_CMD_REQUEST_MESSAGE` — used by QGC to pull messages  
  Source: <https://mavlink.io/en/services/camera_v2.html#message-intervals-and-requests>  
- `MAV_CMD_VIDEO_START_STREAMING (2502)` / `MAV_CMD_VIDEO_STOP_STREAMING (2503)` — push‑stream control (ACK even if you ignore for RTSP/TCP)  
  Source: <https://hamishwillee.gitbooks.io/ham_mavdevguide/en/messages/common.html#mav_cmd_video_start_streaming>

**Gimbal v2**  
- `GIMBAL_MANAGER_INFORMATION (280)` — capabilities, ranges, device id  
  Source: <https://mavlink.io/en/messages/common.html#GIMBAL_MANAGER_INFORMATION>  
- `GIMBAL_MANAGER_STATUS (281)` — periodic manager status  
  Source: <https://mavlink.io/en/messages/common.html#GIMBAL_MANAGER_STATUS>  
- `GIMBAL_MANAGER_SET_ATTITUDE (282)` — control (desired camera frame attitude)  
  Source: <https://mavlink.io/en/messages/common.html#GIMBAL_MANAGER_SET_ATTITUDE>  
- `GIMBAL_DEVICE_INFORMATION (283)` — device metadata (optional for UIs)  
  Source: <https://mavlink.io/en/messages/common.html#GIMBAL_DEVICE_INFORMATION>  
- `GIMBAL_DEVICE_ATTITUDE_STATUS (285)` — broadcast current attitude  
  Source: <https://mavlink.io/en/messages/common.html#GIMBAL_DEVICE_ATTITUDE_STATUS>  
- Protocol overview & discovery flow: <https://mavlink.io/en/services/gimbal_v2.html>

**QGroundControl behavior (user‑level docs & examples)**  
- QGC video UI: <https://docs.qgroundcontrol.com/master/en/qgc-user-guide/fly_view/video.html>  
- Camera tools UI (built from camera definition): <https://docs.qgroundcontrol.com/master/en/qgc-user-guide/fly_view/camera_tools.html>  
- Proof that GCS auto‑shows video from MAVLink camera messages: <https://github.com/mavlink/mavlink-camera-manager#receiving-a-stream-from-a-mavlink-ground-control-station-like-qgroundcontrol>

---

## Robustness & Interop Notes

- **Send one `VIDEO_STREAM_INFORMATION` per stream**; set `count` on each to the same total. QGC uses `stream_id` as a stable selector.  
- For **UDP/RTP** (`VIDEO_STREAM_TYPE_RTPUDP`), the spec allows the **URI to be just the UDP port number** that the GCS should listen on; many implementations also provide a URI QGC accepts (e.g., `udp://0.0.0.0:5600`).  
  Source: [VIDEO_STREAM_INFORMATION — `uri` semantics](https://docs.rs/mavlink/latest/mavlink/common/struct.VIDEO_STREAM_INFORMATION_DATA.html) and spec text linked above.  
- **ACK all `MAV_CMD_XXX`** commands even if you don’t need to act (per MAVLink command protocol).  
- **Multiple cameras**: allocate distinct camera component IDs (`MAV_COMP_ID_CAMERA`, `MAV_COMP_ID_CAMERA2`, …) or use autopilot‑attached `camera_device_id` values 1..6.  
  Source: [ID assignment](https://mavlink.io/en/services/mavlink_id_assignment.html), [Camera v2 “Multiple cameras”](https://mavlink.io/en/services/camera_v2.html#selecting-and-configuring-multiple-cameras)  
- **Definition file compression**: If you host `*.xml.xz`, QGC is expected to decompress.  
  Source: [Camera Definition File](https://mavlink.io/en/services/camera_def.html#file-compression)

---

## Worked Handshake (Happy Path)

Below is a concise sequence diagram‑style outline for a **standalone** MAVLink camera component with one gimbal:

```
QGC ──(listens for HEARTBEAT)───────────────────────────────────────────────┐
Camera ──HEARTBEAT(type=MAV_TYPE_CAMERA, compid=MAV_COMP_ID_CAMERA)───────▶│
QGC ──MAV_CMD_REQUEST_MESSAGE(param1=CAMERA_INFORMATION=259)───────────────▶│
Camera ──CAMERA_INFORMATION(flags includes HAS_VIDEO_STREAM, cam_definition_uri) ▶│
QGC ──MAV_CMD_REQUEST_MESSAGE(param1=VIDEO_STREAM_INFORMATION=269)─────────▶│
Camera ──VIDEO_STREAM_INFORMATION(stream_id=1, count=1, type, uri, encoding) ▶│
QGC ──MAV_CMD_REQUEST_MESSAGE(param1=VIDEO_STREAM_STATUS=270)──────────────▶│
Camera ──VIDEO_STREAM_STATUS(flags=RUNNING, fps, res, bitrate, …)──────────▶│
  (QGC connects to RTSP/TCP; for UDP it listens on the announced port)       │
────────────────────────────────────────────────────────────────────────────┘

# If gimbal present (in same camera component or separate gimbal component):
QGC ──MAV_CMD_REQUEST_MESSAGE(param1=GIMBAL_MANAGER_INFORMATION=280)───────▶
Cam/Gimbal ──GIMBAL_MANAGER_INFORMATION(gimbal_device_id, caps, ranges)────▶
Cam/Gimbal ──GIMBAL_MANAGER_STATUS (≈5 Hz)──────────────────────────────────▶
QGC ──GIMBAL_MANAGER_SET_ATTITUDE (user control, missions, tracking, …)────▶
Cam/Gimbal ──GIMBAL_DEVICE_ATTITUDE_STATUS (broadcast)──────────────────────▶
```

Sources: [Camera v2](https://mavlink.io/en/services/camera_v2.html), [Gimbal v2](https://mavlink.io/en/services/gimbal_v2.html)

---

## Notes for **Elixir + `xmavlink`** (non‑normative)

- The `xmavlink_util` docs expose helpers/enums (e.g., `video_stream_type/0`, `video_stream_status_flags/0`, `camera_capability_flags/0`).  
  See: <https://hexdocs.pm/xmavlink_util/Common.html> and <https://hexdocs.pm/xmavlink_util/Common.Types.html>  
- In practice you will:
  1) Start a MAVLink endpoint (UDP/TCP) and emit `HEARTBEAT` at 1 Hz.  
  2) Handle `COMMAND_LONG` for `MAV_CMD_REQUEST_MESSAGE` and respond with the requested message.  
  3) Maintain state per `stream_id` and periodically publish `VIDEO_STREAM_STATUS` when running.  
  4) If implementing gimbal v2, keep a supervisor/GenServer that tracks the last `GIMBAL_MANAGER_SET_ATTITUDE` and updates your pan/tilt device.

This section is just a convenience pointer; **the normative behavior is defined by the links above**.

---

## References (Primary)

- **MAVLink Camera Protocol v2 (spec & flows)**  
  <https://mavlink.io/en/services/camera_v2.html>

- **Message definitions — `common.xml`**  
  `HEARTBEAT`, `CAMERA_INFORMATION (259)`, `VIDEO_STREAM_INFORMATION (269)`, `VIDEO_STREAM_STATUS (270)`, `GIMBAL_*` messages, `VIDEO_STREAM_TYPE` enum and others.  
  <https://mavlink.io/en/messages/common.html>

- **Camera Definition File** (schema, compression, common parameters)  
  <https://mavlink.io/en/services/camera_def.html>

- **Gimbal Protocol v2** (discovery, capabilities, control)  
  <https://mavlink.io/en/services/gimbal_v2.html>

- **MAVLink System & Component ID assignment** (sysid/compid, types)  
  <https://mavlink.io/en/services/mavlink_id_assignment.html>

- **QGroundControl User Docs — Video & Camera Tools (UI)**  
  <https://docs.qgroundcontrol.com/master/en/qgc-user-guide/fly_view/video.html>  
  <https://docs.qgroundcontrol.com/master/en/qgc-user-guide/fly_view/camera_tools.html>

- **Example implementation claim** that video auto‑appears in modern GCS (QGC) when camera messages are provided  
  <https://github.com/mavlink/mavlink-camera-manager#receiving-a-stream-from-a-mavlink-ground-control-station-like-qgroundcontrol>

---

### Appendix: Quick Field Cheat‑Sheet

**`CAMERA_INFORMATION (259)`** (key fields to set)  
- `vendor_name`, `model_name`, `firmware_version`  
- `focal_length`, `sensor_size_h`, `sensor_size_v` (optional)  
- `resolution_h`, `resolution_v` (0 if unknown)  
- `lens_id` (0 if unknown)  
- `flags` (**include `HAS_VIDEO_STREAM`** if streaming)  
- `cam_definition_version` (0 if unknown), `cam_definition_uri` (`http://` or `mavlinkftp://`, can be `.xml.xz`)  
- `gimbal_device_id` (0 if none)  
- `camera_device_id` (1..6 for autopilot‑attached; 0 for standalone)

**`VIDEO_STREAM_INFORMATION (269)`**  
- `stream_id` (1..N), `count` (N), `type (VIDEO_STREAM_TYPE)`, `name[32]`, `uri[160]` (port or URI per type), `encoding (VIDEO_STREAM_ENCODING)`

**`VIDEO_STREAM_STATUS (270)`**  
- `flags (VIDEO_STREAM_STATUS_FLAGS)`, `framerate`, `resolution_h/v`, `bitrate`, `rotation`, `hfov`
