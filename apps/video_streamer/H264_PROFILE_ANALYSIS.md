# H.264 Profile Analysis for Drone Video Streaming

## Current Configuration
- **Profile**: Baseline (`--profile baseline`)
- **Profile-Level-ID**: 42C01F (Constrained Baseline, Level 3.1)
- **Resolution**: 1280x720 @ 30fps
- **Hardware**: Raspberry Pi CM4 with hardware H.264 encoder
- **Use Case**: Low-latency streaming from drone to ground station (phone/tablet)

## H.264 Profile Comparison

### Available Profiles in rpicam-vid
1. **Baseline** (current)
2. **Main**
3. **High**

### Technical Differences

| Feature | Baseline | Main | High |
|---------|----------|------|------|
| **Entropy Coding** | CAVLC | CABAC | CABAC |
| **B-frames** | ❌ No | ✅ Yes | ✅ Yes |
| **Compression Efficiency** | Lowest | Medium | Highest |
| **Bandwidth (same quality)** | Highest | Medium | Lowest |
| **Encoding Complexity** | Low | Medium | High |
| **Decoding Complexity** | Low | Medium | High |
| **Device Compatibility** | Universal | Modern | Very Modern |
| **Battery Impact (decoder)** | Low | Medium | Higher |

### Compression Efficiency
At the same quality level:
- **Main Profile**: ~10-15% better compression than Baseline
- **High Profile**: ~20-30% better compression than Baseline

This means:
- Baseline @ 3 Mbps ≈ Main @ 2.6 Mbps ≈ High @ 2.2 Mbps (same visual quality)

## Analysis for Your Use Case

### Scenario: Drone → Phone/Tablet Streaming

**Network Constraints:**
- ✅ WiFi: 10.5.0.0/24 network (good bandwidth)
- ⚠️ Potential Future: Cellular/LTE (limited bandwidth)
- ⚠️ Potential Future: Long-range RF links (very limited)

**Device Constraints:**
- ✅ Modern iOS/Android devices (2020+)
- ✅ QGroundControl on laptops (powerful)
- ⚠️ Older tablets or phones in the field

**Raspberry Pi CM4 Encoder:**
- ✅ Hardware H.264 encoder (efficient)
- ✅ Supports all profiles: Baseline, Main, High
- ✅ Real-time encoding at 720p30 (no performance issue)

## Recommendations

### Current Choice: Baseline ⚠️ RECONSIDER

**Why we chose it:**
- Debugging iOS VLC (turned out to be VLC bug, not profile issue)
- Maximum compatibility

**Downsides:**
- 10-30% higher bandwidth than necessary
- Less efficient for constrained networks
- Wasted encoding capability of CM4

### Recommended: Main Profile ✅ BEST CHOICE

**Advantages:**
1. **Better Compression**: 10-15% bandwidth savings vs Baseline
2. **Modern Device Support**: All iOS 5+, Android 4+, QGC support Main
3. **Drone Use Case**: Lower bandwidth = better range, more reliable
4. **Battery Efficient**: CABAC decoding is hardware-accelerated on modern devices
5. **CM4 Can Handle It**: Hardware encoder supports Main with no performance penalty

**Profile-Level-ID**: `4D401F` (Main Profile, Level 3.1)

**Real-World Impact:**
- Baseline: ~2.5 Mbps for 720p30 decent quality
- Main: ~2.1 Mbps for same quality
- **Savings**: 400 Kbps = better range, less packet loss

### Alternative: High Profile ⚠️ OVERKILL

**Advantages:**
- Maximum compression (20-30% savings)
- Best for very constrained networks

**Disadvantages:**
- Some older devices may struggle
- Slightly higher CPU on decoder (battery impact on phones)
- Marginal benefit over Main for 720p30

**When to use:**
- 1080p or higher resolution
- Very bandwidth-constrained links (LTE, RF)
- Known modern devices only

## Compatibility Check

### Main Profile (4D401F) Support

**iOS Devices:**
- ✅ iOS 5+ (2011+): Full Main Profile support
- ✅ Hardware decoding on A7+ chips (iPhone 5s+, 2013+)
- ✅ All iPads since 2013

**Android Devices:**
- ✅ Android 4.0+ (2011+): Main Profile support
- ✅ Hardware decoding on most devices since 2012

**QGroundControl:**
- ✅ Desktop: Full support (any profile)
- ✅ Mobile: Main Profile supported

**VLC:**
- ✅ macOS VLC: All profiles
- ⚠️ iOS VLC: Has bugs with ANY profile over UDP (we documented this)

**IP Camera Viewer (iOS):**
- ✅ Tested working with Constrained Baseline
- ✅ Should work with Main Profile (modern decoder)

## Bandwidth Impact Analysis

### Current (Baseline @ 720p30):
```
Bitrate: ~2.5 Mbps (estimated)
RTP overhead: ~200 Kbps
Total: ~2.7 Mbps
```

### With Main Profile @ 720p30:
```
Bitrate: ~2.1 Mbps (15% savings)
RTP overhead: ~170 Kbps (less data)
Total: ~2.27 Mbps
Savings: ~430 Kbps (16% total bandwidth reduction)
```

### Why This Matters for Drones:
1. **Longer Range**: 16% less bandwidth = more robust over WiFi at distance
2. **Better in Interference**: Less data = fewer retransmissions needed
3. **Future-Proof**: If you add LTE/RF links, lower bandwidth is critical
4. **Multi-Client**: With Main, you could support more simultaneous viewers

## Migration Plan

### Phase 1: Test Main Profile (Low Risk)
1. Change `--profile baseline` to `--profile main` in source.ex
2. Update SDP profile-level-id from `42C01F` to `4D401F`
3. Test with:
   - macOS VLC ✓
   - iOS IP Camera Viewer ✓
   - QGroundControl (when available)
4. Verify bandwidth reduction with network monitoring

### Phase 2: Extract New SPS/PPS
Main Profile will have different SPS/PPS structure:
1. Capture stream: `ffmpeg -i rtsp://ip:8554/video -vframes 1 -c copy -f h264`
2. Extract SPS/PPS from Main Profile stream
3. Update SDP with new sprop-parameter-sets
4. Verify all clients still work

### Phase 3: Measure & Document
- Measure actual bitrate reduction
- Test video quality at same bitrate vs Baseline
- Test at longer WiFi distances
- Document findings in Phase 5

## Code Changes Required

### 1. Update Camera Profile
**File**: `apps/video_streamer/lib/membrane_rpicam/source.ex:157`
```elixir
# Change from:
--profile baseline

# To:
--profile main
```

### 2. Update SDP Profile-Level-ID
**File**: `apps/video_streamer/lib/video_streamer/rtsp/sdp.ex:87`
```elixir
# Change from:
profile_level_id = Map.get(codec_params, :profile_level_id, "42C01F")

# To:
profile_level_id = Map.get(codec_params, :profile_level_id, "4D401F")
```

### 3. Extract & Update SPS/PPS
After deploying Main Profile, capture new SPS/PPS and update:
**File**: `apps/video_streamer/lib/video_streamer/rtsp/sdp.ex:97`
```elixir
# Will change from Baseline SPS/PPS:
default_sps_pps = "Z0LAH9oBQBbpqAgICgAAAwACAD0JAB4wZUA=,aM4PyA=="

# To Main Profile SPS/PPS (extract from stream after changing profile)
default_sps_pps = "<NEW_MAIN_PROFILE_SPS_PPS>"
```

## Decision Matrix

| Use Case | Baseline | Main | High |
|----------|----------|------|------|
| Unknown old devices | ✅ Best | ⚠️ Risky | ❌ No |
| Modern devices (2015+) | ⚠️ Wasteful | ✅ Best | ✅ Good |
| Limited bandwidth | ❌ Poor | ✅ Good | ✅ Best |
| Ultra-low latency | ✅ Good | ✅ Good | ⚠️ OK |
| Battery sensitive | ✅ Best | ✅ Good | ⚠️ OK |
| Drone streaming | ⚠️ OK | ✅ **BEST** | ✅ Good |

## Conclusion

### Answer: Should You Change?

**YES - Switch to Main Profile** for these reasons:

1. ✅ **Your devices support it**: Modern iOS/Android/QGC all support Main
2. ✅ **Better for drones**: 15% bandwidth savings = better range/reliability
3. ✅ **No performance penalty**: CM4 hardware encoder handles it
4. ✅ **Future-proof**: If you add LTE/RF, you'll need the efficiency
5. ✅ **Already debugged iOS**: The iOS VLC issue was VLC bug, not profile-related

### What You Were Using Before

Looking at git history, you likely started with **High Profile** (default for rpicam-vid), then changed to Baseline for iOS debugging. Main Profile is the sweet spot between them.

### Action Items

1. ✅ Document this analysis (this file)
2. ⬜ Test Main Profile in Phase 4/5 deployment
3. ⬜ Measure bandwidth improvement
4. ⬜ Update documentation with findings
5. ⬜ Consider making profile configurable via environment variable

---

**Recommendation**: Change to Main Profile (4D401F) - better compression, still universal compatibility, perfect for drone streaming.

**When**: During Phase 4 (containerization) or Phase 5 (optimization)

**Risk**: Very Low (Main supported since 2011, all your target devices support it)
