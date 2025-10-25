# Model Export Guide: YOLO Models for VideoAnnotator

This guide explains how to obtain YOLO models in ONNX format for use with the VideoAnnotator application.

**Two Options:**
1. **YOLOv11 Export (Recommended):** Export latest YOLOv11 models from PyTorch to ONNX
2. **Pre-converted YOLOX:** Use pre-converted YOLOX models (quick alternative, no export needed)

## Prerequisites

### Software Requirements (Option 1 only)
- Python 3.10 or later
- pip (Python package manager)

### Hardware Requirements
- Any development machine (export doesn't require GPU)
- ~2GB free disk space for models and dependencies

## Option 1: Export YOLOv11 Models (Recommended)

### Why YOLOv11?

**Advantages:**
- ✅ **Latest YOLO architecture** - State-of-the-art performance (2024)
- ✅ **Better accuracy** - YOLOv11n: 39.5% mAP vs YOLOX-Nano: 25.8% mAP
- ✅ **More features** - Pose estimation, segmentation, oriented bounding boxes
- ✅ **Custom training** - Easy to fine-tune on your own dataset
- ✅ **Active development** - Regular updates from Ultralytics

**When to use YOLOX instead:**
- Want pre-converted models (no Python setup)
- Need to get started in <5 minutes
- Prefer smaller model files

### Quick Export (CLI Method)

```bash
# Install Ultralytics
pip install ultralytics

# Export YOLOv11n to ONNX
yolo export model=yolo11n.pt format=onnx imgsz=640 simplify=True

# Model will be saved as yolo11n.onnx (~6 MB)
```

### Detailed Export Process

#### 1. Install Dependencies

```bash
# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install Ultralytics (includes PyTorch and all dependencies)
pip install ultralytics

# Optional: Install ONNX Runtime for validation
pip install onnxruntime
```

#### 2. Export Model Using Python Script

Create `scripts/export_yolo11.py`:

```python
#!/usr/bin/env python3
"""
Export YOLOv11 models to ONNX format for VideoAnnotator.

Usage:
    python scripts/export_yolo11.py [--model MODEL] [--size SIZE]

Examples:
    python scripts/export_yolo11.py --model yolo11n --size 640
    python scripts/export_yolo11.py --model yolo11s --size 416
"""

import argparse
from pathlib import Path
from ultralytics import YOLO


def export_yolo_to_onnx(model_name, imgsz=640, simplify=True, opset=12):
    """
    Export YOLOv11 model to ONNX format.

    Args:
        model_name: Model variant (yolo11n, yolo11s, yolo11m, yolo11l, yolo11x)
        imgsz: Input image size (640, 416, 320)
        simplify: Simplify ONNX graph for better performance
        opset: ONNX opset version (11 or 12 recommended)
    """
    print(f"Exporting {model_name} to ONNX format...")
    print(f"  Image size: {imgsz}")
    print(f"  Simplify: {simplify}")
    print(f"  Opset: {opset}")

    # Load pretrained model (auto-downloads if not cached)
    model = YOLO(f'{model_name}.pt')

    # Export to ONNX
    export_path = model.export(
        format='onnx',
        imgsz=imgsz,
        simplify=simplify,
        opset=opset,
        dynamic=False,  # Fixed input shape for embedded performance
    )

    print(f"✓ Model exported successfully to: {export_path}")
    return export_path


def main():
    parser = argparse.ArgumentParser(description='Export YOLOv11 to ONNX')
    parser.add_argument('--model', type=str, default='yolo11n',
                        choices=['yolo11n', 'yolo11s', 'yolo11m', 'yolo11l', 'yolo11x'],
                        help='Model variant to export')
    parser.add_argument('--size', type=int, default=640,
                        choices=[320, 416, 640],
                        help='Input image size')
    parser.add_argument('--opset', type=int, default=12,
                        help='ONNX opset version')
    parser.add_argument('--no-simplify', action='store_true',
                        help='Disable ONNX graph simplification')

    args = parser.parse_args()

    export_yolo_to_onnx(
        model_name=args.model,
        imgsz=args.size,
        simplify=not args.no_simplify,
        opset=args.opset
    )


if __name__ == '__main__':
    main()
```

Run the export:

```bash
chmod +x scripts/export_yolo11.py
python scripts/export_yolo11.py --model yolo11n --size 640
```

### Model Variants

YOLOv11 comes in 5 sizes:

| Model | Params | mAP (COCO) | Speed (CPU) | Recommended Use |
|-------|--------|------------|-------------|-----------------|
| **yolo11n** | 2.6M | 39.5% | **Good** | **Raspberry Pi (Recommended)** |
| yolo11s | 9.4M | 47.0% | Medium | Good balance |
| yolo11m | 20.1M | 51.5% | Slow | Desktop inference |
| yolo11l | 25.3M | 53.4% | Slower | High accuracy needed |
| yolo11x | 56.9M | 54.7% | Slowest | Maximum accuracy |

**For Raspberry Pi 5/CM5:** Use `yolo11n` (nano) for best performance (~8 FPS).

### Download COCO Classes

```bash
# Download class labels
curl -L -o coco_classes.json https://raw.githubusercontent.com/amikelive/coco-labels/master/coco-labels-2014_2017.json
```

### Move to VideoAnnotator

```bash
# Create models directory
mkdir -p apps/video_annotator/priv/models

# Move exported model and classes
mv yolo11n.onnx apps/video_annotator/priv/models/
mv coco_classes.json apps/video_annotator/priv/models/

# Verify
ls -lh apps/video_annotator/priv/models/
```

### Use in yolo_elixir

```elixir
# Load YOLOv11 model
model = YOLO.load(
  model_impl: YOLO.Models.Ultralytics,
  model_path: "priv/models/yolo11n.onnx",
  classes_path: "priv/models/coco_classes.json"
)

# Run detection
detections = model
  |> YOLO.detect(image_tensor)
  |> YOLO.to_detected_objects(model.classes)
```

---

## Option 2: Pre-Converted YOLOX Models (Quick Alternative)

### Why YOLOX as Alternative?

**Advantages:**
- ✅ **No Python setup required** - Just download and use
- ✅ **Pre-tested** with yolo_elixir library
- ✅ **Smaller models** - YOLOX-Nano (0.91M params) vs YOLOv11n (2.6M params)
- ✅ **Faster iteration** - Get started in <5 minutes
- ✅ **Slightly faster inference** - ~12 FPS vs ~8 FPS on Pi 5

**Trade-offs:**
- Lower accuracy (25.8% vs 39.5% mAP)
- Older architecture (2021 vs 2024)
- Fewer features (no pose/segmentation)

### Download Pre-Converted YOLOX Models

Available models from [YOLOX GitHub](https://github.com/Megvii-BaseDetection/YOLOX/releases):

| Model | Size | mAP (COCO) | Speed (Pi 5)* | Recommended For |
|-------|------|-----------|---------------|-----------------|
| **YOLOX-Nano** | 0.91M | 25.8% | ~12 FPS | **Quick start, development** |
| YOLOX-Tiny | 5.06M | 32.8% | ~10 FPS | Good accuracy/speed balance |
| YOLOX-S | 9.0M | 40.5% | ~6 FPS | Better accuracy |
| YOLOX-M | 25.3M | 47.2% | ~3 FPS | High accuracy |
| YOLOX-L | 54.2M | 50.1% | ~1 FPS | Maximum accuracy |

\* Estimated FPS on Raspberry Pi 5

### Quick Download Script

```bash
# Create models directory
mkdir -p apps/video_annotator/priv/models
cd apps/video_annotator/priv/models

# Download YOLOX-Nano (recommended for quick start)
curl -L -O https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_nano.onnx

# Download COCO classes
curl -L -o coco_classes.json https://raw.githubusercontent.com/amikelive/coco-labels/master/coco-labels-2014_2017.json

# Verify download
ls -lh
# Expected:
# yolox_nano.onnx (~3.8 MB)
# coco_classes.json (~2 KB)
```

### Use in yolo_elixir

```elixir
# Load YOLOX model
model = YOLO.load(
  model_impl: YOLO.Models.YOLOX,
  model_path: "priv/models/yolox_nano.onnx",
  classes_path: "priv/models/coco_classes.json"
)

# Run detection
detections = model
  |> YOLO.detect(image_tensor)
  |> YOLO.to_detected_objects(model.classes)
```

**Note:** YOLOX expects 416x416 input (vs 640x640 for YOLOv11)

---

## Comparison: YOLOv11 vs YOLOX

| Aspect | YOLOv11n | YOLOX-Nano |
|--------|----------|------------|
| **Setup Time** | ~10 mins (export) | ~2 mins (download) |
| **Python Required** | Yes (one-time) | No |
| **Model Size** | ~6 MB | ~3.8 MB |
| **Parameters** | 2.6M | 0.91M |
| **mAP (COCO)** | **39.5%** ✅ | 25.8% |
| **FPS (Pi 5)** | ~8 FPS | **~12 FPS** ✅ |
| **Input Size** | 640x640 | 416x416 |
| **Features** | Pose, segmentation, OBB | Detection only |
| **Architecture** | 2024 (latest) | 2021 |
| **Recommended For** | **Production** | Quick start/dev |

## Troubleshooting

### Model Export Fails

**Error:** `ModuleNotFoundError: No module named 'ultralytics'`

**Solution:**
```bash
pip install ultralytics
```

### ONNX Export Error

**Error:** `ONNX export failed with opset error`

**Solution:** Try different opset version:
```bash
yolo export model=yolo11n.pt format=onnx opset=11
```

### Model Too Large

**Error:** Out of memory on Raspberry Pi

**Solution:** Use smaller model variant:
- Try `yolo11n` instead of `yolo11s`
- Or use YOLOX-Nano (smallest available)

## Performance Benchmarks

Expected inference times (single image):

### YOLOv11n (640x640)
| Platform | Format | Inference Time | FPS |
|----------|--------|----------------|-----|
| Raspberry Pi 5 | ONNX | ~125ms | ~8 |
| macOS (M1, CoreML) | ONNX | ~50ms | ~20 |
| Desktop (i7 CPU) | ONNX | ~80ms | ~12 |

### YOLOX-Nano (416x416)
| Platform | Format | Inference Time | FPS |
|----------|--------|----------------|-----|
| Raspberry Pi 5 | ONNX | ~80ms | ~12 |
| macOS (M1, CoreML) | ONNX | ~30ms | ~30 |
| Desktop (i7 CPU) | ONNX | ~50ms | ~20 |

## References

- [Ultralytics YOLOv11 Documentation](https://docs.ultralytics.com/models/yolo11/)
- [ONNX Export Guide](https://docs.ultralytics.com/modes/export/)
- [YOLOX GitHub](https://github.com/Megvii-BaseDetection/YOLOX)
- [yolo_elixir Documentation](https://hexdocs.pm/yolo_elixir)
- [ONNX Runtime Documentation](https://onnxruntime.ai/docs/)

## Next Steps

After obtaining your model:

1. Verify model works (optional Python test)
2. Move model to `apps/video_annotator/priv/models/`
3. Test inference in Elixir with yolo_elixir
4. Integrate with VideoAnnotator application
5. Deploy to Raspberry Pi and test performance

For questions or issues, refer to the [implementation plan](implementation_plan.md) or [phase0-quickstart.md](phase0-quickstart.md).
