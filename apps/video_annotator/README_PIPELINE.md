# Video Annotation Pipeline - Quick Reference

## Starting the Web Preview

```bash
cd /Users/royveshovda/src/fancydrones/x500-cm4/apps/video_annotator
mix run test_web_preview.exs
```

Then open **http://localhost:4001** in your browser.

## Architecture Summary

**Flow**: Camera (30 FPS) → Toilet (capacity: 1) → YoloDetector (adaptive ~6-7 FPS) → Sink

**Key Features**:
- ✅ Auto flow control (push-based)
- ✅ Time-based adaptive frame skipping (270ms target)
- ✅ Two-level frame dropping (toilet + time-based)
- ✅ Low latency preview (< 100ms)
- ✅ Automatic CPU load adaptation

## Core Implementation

### Time-Based Frame Skipping (yolo_detector.ex)

```elixir
def handle_buffer(:input, buffer, ctx, state) do
  current_time = System.monotonic_time(:millisecond)
  time_since_last = current_time - state.last_process_time

  if time_since_last < state.target_interval_ms && state.frame_count > 0 do
    # Skip frame - too soon
    {[buffer: {:output, buffer}], state}
  else
    # Process frame
    # ... inference, annotation, preview ...
    new_state = %{state | last_process_time: current_time, ...}
    {[buffer: {:output, buffer}], new_state}
  end
end
```

### Pipeline Configuration (pipeline.ex)

```elixir
child(:camera, %Membrane.CameraCapture{device: camera, framerate: 30})
|> via_in(:input, toilet_capacity: 1)  # Keep only latest frame
|> child(:yolo_detector, %VideoAnnotator.YoloDetector{...})
|> child(:sink, Membrane.Fake.Sink.Buffers)
```

## Key Parameters

| Parameter | Location | Value (macOS) | Recommended (RPi) |
|-----------|----------|---------------|-------------------|
| `target_interval_ms` | yolo_detector.ex:57 | 270ms | 500-600ms |
| `toilet_capacity` | pipeline.ex:44 | 1 | 1 |
| `camera framerate` | pipeline.ex:39 | 30 FPS | 30 FPS |
| `preview max-width` | web_preview.ex:87 | 50% | 50% |

## Adaptation Behavior

The pipeline **automatically adapts** to CPU load:

- **Normal**: 6-7 FPS (270ms per frame)
- **Heavy load**: 2-4 FPS (inference takes longer, automatically spaces out)
- **Buffered frames**: Immediately skipped (time-based check)

**No manual intervention needed** - it just works!

## Critical Learnings

### ✅ DO

1. **Use auto flow control** (not manual) - simpler, no compatibility issues
2. **Implement time-based skipping** - essential for low latency
3. **Use toilet_capacity: 1** - prevents memory buildup
4. **Update last_process_time AFTER processing** - not before
5. **Calculate FPS before sending to preview** - ensures accurate stats
6. **Scale image in preview** - prevents vertical overflow

### ❌ DON'T

1. **Don't use manual flow control** - causes toilet overflow with Camera
2. **Don't rely only on toilet** - still processes buffered frames
3. **Don't skip preview_interval check removal** - needed for low latency
4. **Don't forget frame-ID tracking in preview** - prevents repeated frames
5. **Don't use 100% image width** - causes vertical overflow

## For Raspberry Pi Deployment

### Adjust Target Interval

In `yolo_detector.ex`, line 57:
```elixir
target_interval_ms: 500  # Changed from 270 for slower RPi
```

### Monitor Performance

Watch logs for adaptation:
```bash
Frame 30: 1 detections, 450ms inference, avg 480.0ms (2.1 FPS)
Frame 60: 1 detections, 520ms inference, avg 495.0ms (2.0 FPS)
```

If FPS too low, consider:
- Lower camera resolution (640x480)
- Smaller YOLO input (416x416 or 320x320)
- Skip annotation drawing
- Use quantized model

## File Reference

- **[PIPELINE_ARCHITECTURE.md](PIPELINE_ARCHITECTURE.md)** - Complete technical documentation
- **[yolo_detector.ex](lib/video_annotator/yolo_detector.ex)** - Time-based skipping implementation
- **[pipeline.ex](lib/video_annotator/pipeline.ex)** - Pipeline configuration
- **[web_preview.ex](lib/video_annotator/web_preview.ex)** - Web preview server
- **[test_web_preview.exs](test_web_preview.exs)** - Start script

## Troubleshooting

### Preview shows no image
```bash
pkill -9 beam.smp
mix clean && mix compile
mix run test_web_preview.exs
# Hard refresh browser (Cmd+Shift+R)
```

### Preview lags behind
- Check time-based skipping is enabled
- Verify `last_process_time` updated after processing
- Ensure `toilet_capacity: 1` is set

### FPS not updating
- Check `fps` parameter passed to `save_preview_frame`
- Verify statistics calculated before preview update

## Performance Expectations

### macOS (Development)
- Camera: 30 FPS
- Processing: 6-7 FPS
- Inference: 130-180ms
- Latency: < 100ms

### Raspberry Pi 4 (Estimated)
- Camera: 30 FPS
- Processing: 2-4 FPS
- Inference: 300-500ms
- Latency: < 150ms

## Success Criteria

✅ Preview shows live video with bounding boxes
✅ FPS counter updates every second
✅ No vertical overflow on preview page
✅ Minimal lag when moving camera (< 200ms)
✅ System adapts to CPU load automatically
✅ No "Toilet overflow" errors in logs

---

**Status**: ✅ Working correctly on macOS, ready for RPi deployment

**Last Updated**: 2025-10-26
