# Model Export Guide: YOLOv11 to ONNX

This guide explains how to export YOLOv11 models from PyTorch format to ONNX format for use with the VideoAnnotator application.

## Prerequisites

### Software Requirements
- Python 3.10 or later
- PyTorch 2.0+
- Ultralytics package (`pip install ultralytics`)
- ONNX Runtime (`pip install onnxruntime`)

### Hardware Requirements
- Any development machine (export doesn't require GPU)
- ~2GB free disk space for models and dependencies

## Quick Start

### 1. Install Dependencies

```bash
# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install Ultralytics (includes all dependencies)
pip install ultralytics

# Optional: Install ONNX Runtime for validation
pip install onnxruntime
```

### 2. Export YOLOv11n Model

```bash
# Export using CLI
yolo export model=yolo11n.pt format=onnx imgsz=640 simplify=True opset=12

# Or using Python script (see below)
python scripts/export_yolo11.py
```

### 3. Verify Exported Model

```bash
# Check ONNX model
python scripts/verify_onnx.py yolo11n.onnx
```

## Detailed Export Process

### Python Script Method

Create a Python script for reproducible exports:

**File:** `scripts/export_yolo11.py`

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

    # Load pretrained model
    # Will auto-download if not cached
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

    # Verify exported model
    verify_onnx_model(export_path)

    return export_path


def verify_onnx_model(onnx_path):
    """Verify ONNX model can be loaded and basic structure is correct."""
    try:
        import onnx
        import onnxruntime as ort

        # Check ONNX model structure
        onnx_model = onnx.load(onnx_path)
        onnx.checker.check_model(onnx_model)
        print("✓ ONNX model structure valid")

        # Check inference session can be created
        session = ort.InferenceSession(onnx_path)
        print(f"✓ ONNX Runtime session created")

        # Print input/output info
        print("\nModel Details:")
        print("Inputs:")
        for input in session.get_inputs():
            print(f"  - {input.name}: {input.shape} ({input.type})")

        print("Outputs:")
        for output in session.get_outputs():
            print(f"  - {output.name}: {output.shape} ({output.type})")

    except ImportError:
        print("⚠ ONNX/ONNXRuntime not installed, skipping verification")
        print("  Install with: pip install onnx onnxruntime")
    except Exception as e:
        print(f"✗ Error verifying model: {e}")
        raise


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

Make script executable:
```bash
chmod +x scripts/export_yolo11.py
```

### Model Variants

YOLOv11 comes in 5 sizes:

| Model | Params | mAP (COCO) | Speed (CPU) | Recommended Use |
|-------|--------|------------|-------------|-----------------|
| yolo11n | 2.6M | 39.5% | **Fastest** | **Raspberry Pi (Recommended)** |
| yolo11s | 9.4M | 47.0% | Fast | Good balance |
| yolo11m | 20.1M | 51.5% | Medium | Desktop inference |
| yolo11l | 25.3M | 53.4% | Slow | High accuracy needed |
| yolo11x | 56.9M | 54.7% | Slowest | Maximum accuracy |

**For Raspberry Pi 5/CM5:** Use `yolo11n` (nano) for best performance (≥8 FPS).

### Image Size Trade-offs

| Size | Speed | Accuracy | Memory | Recommendation |
|------|-------|----------|--------|----------------|
| 320 | Fastest | Lower | Lowest | Low latency critical |
| 416 | Fast | Good | Low | Good balance |
| **640** | Medium | **Best** | Medium | **Default (Recommended)** |

## Verification Script

**File:** `scripts/verify_onnx.py`

```python
#!/usr/bin/env python3
"""
Verify ONNX model and test inference.

Usage:
    python scripts/verify_onnx.py model.onnx [--image test.jpg]
"""

import argparse
import numpy as np
import onnxruntime as ort
from PIL import Image


def verify_and_test_model(onnx_path, test_image=None):
    """Verify ONNX model and optionally run test inference."""

    print(f"Loading ONNX model: {onnx_path}")

    # Create inference session
    session = ort.InferenceSession(onnx_path)

    # Print model info
    print("\n=== Model Information ===")
    print(f"Providers: {session.get_providers()}")

    print("\nInputs:")
    for inp in session.get_inputs():
        print(f"  {inp.name}: shape={inp.shape}, type={inp.type}")

    print("\nOutputs:")
    for out in session.get_outputs():
        print(f"  {out.name}: shape={out.shape}, type={out.type}")

    # Test inference if image provided
    if test_image:
        print(f"\n=== Running Test Inference ===")
        test_inference(session, test_image)
    else:
        print(f"\n=== Running Test with Random Data ===")
        test_random_inference(session)


def test_inference(session, image_path):
    """Run inference on a real image."""
    from PIL import Image
    import numpy as np

    # Load and preprocess image
    img = Image.open(image_path).convert('RGB')
    img = img.resize((640, 640))

    # Convert to numpy array and preprocess
    img_array = np.array(img).astype(np.float32)
    img_array = img_array / 255.0  # Normalize to [0, 1]

    # Transpose to (C, H, W) format
    img_array = np.transpose(img_array, (2, 0, 1))

    # Add batch dimension
    img_array = np.expand_dims(img_array, axis=0)

    print(f"Input shape: {img_array.shape}")

    # Run inference
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: img_array})

    print(f"Output shape: {outputs[0].shape}")
    print("✓ Inference successful!")


def test_random_inference(session):
    """Run inference with random data to verify model loads."""
    # Get expected input shape
    input_shape = session.get_inputs()[0].shape

    # Handle dynamic batch dimension
    if isinstance(input_shape[0], str):
        input_shape = [1] + input_shape[1:]

    print(f"Creating random input: {input_shape}")

    # Create random input
    random_input = np.random.rand(*input_shape).astype(np.float32)

    # Run inference
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: random_input})

    print(f"Output shape: {outputs[0].shape}")
    print("✓ Model loaded and inference successful!")


def main():
    parser = argparse.ArgumentParser(description='Verify ONNX model')
    parser.add_argument('model', type=str, help='Path to ONNX model')
    parser.add_argument('--image', type=str, help='Test image (optional)')

    args = parser.parse_args()

    verify_and_test_model(args.model, args.image)


if __name__ == '__main__':
    main()
```

## Deployment to VideoAnnotator

### 1. Copy Model to Application

```bash
# From repository root
cp yolo11n.onnx apps/video_annotator/priv/models/

# Verify model is in place
ls -lh apps/video_annotator/priv/models/yolo11n.onnx
```

### 2. Configure VideoAnnotator

**File:** `config/runtime.exs`

```elixir
if config_env() == :prod do
  config :video_annotator,
    models_dir: "/app/priv/models",
    default_model: "yolo11n",
    confidence_threshold: 0.5
end
```

### 3. Test in Development

```elixir
# In IEx
{:ok, model} = VideoAnnotator.ModelLoader.load_model("yolo11n")

# Test inference
test_image = Nx.random_uniform({1, 3, 640, 640})
result = Nx.Serving.batched_run(:yolo_detection, test_image)
```

## Advanced: Custom Model Export

### Export Custom Trained Model

If you've trained a custom YOLOv11 model:

```python
from ultralytics import YOLO

# Load your custom model
model = YOLO('path/to/your/best.pt')

# Export to ONNX
model.export(
    format='onnx',
    imgsz=640,
    simplify=True,
    opset=12,
    # Include custom class names
    data='path/to/your/dataset.yaml'
)
```

### Export with INT8 Quantization

For better performance on embedded devices:

```python
model = YOLO('yolo11n.pt')

model.export(
    format='onnx',
    imgsz=640,
    simplify=True,
    opset=12,
    int8=True,  # Enable INT8 quantization
    data='coco128.yaml'  # Calibration dataset
)
```

**Note:** INT8 quantization requires calibration dataset and may reduce accuracy slightly (1-2% mAP drop) for significant speed improvements.

## Troubleshooting

### Issue: Model download fails

**Solution:** Download manually from [Ultralytics releases](https://github.com/ultralytics/assets/releases):

```bash
wget https://github.com/ultralytics/assets/releases/download/v0.0.0/yolo11n.pt
```

### Issue: ONNX export fails with opset error

**Solution:** Try different opset version:

```python
model.export(format='onnx', opset=11)  # Try opset 11 instead of 12
```

### Issue: Exported model too large

**Solution:** Use a smaller variant or enable simplification:

```python
# Use nano model
model = YOLO('yolo11n.pt')

# Ensure simplify=True
model.export(format='onnx', simplify=True)
```

### Issue: Runtime error in ONNX Runtime

**Solution:** Verify ONNX Runtime version compatibility:

```bash
pip install onnxruntime==1.16.0  # Known working version
```

## Performance Benchmarks

Expected inference times (single image, 640x640):

| Platform | Model | Format | Inference Time |
|----------|-------|--------|----------------|
| Raspberry Pi 5 | yolo11n | ONNX | ~94ms |
| Raspberry Pi 5 | yolo11n | ONNX (INT8) | ~60ms |
| Desktop CPU (Intel i7) | yolo11n | ONNX | ~25ms |
| Desktop GPU (RTX 3080) | yolo11n | ONNX | ~3ms |

## References

- [Ultralytics YOLOv11 Documentation](https://docs.ultralytics.com/models/yolo11/)
- [ONNX Export Guide](https://docs.ultralytics.com/modes/export/)
- [ONNX Runtime Documentation](https://onnxruntime.ai/docs/)
- [Ortex Documentation](https://hexdocs.pm/ortex)

## Next Steps

After exporting your model:

1. Verify model works with verification script
2. Copy model to `apps/video_annotator/priv/models/`
3. Test inference in Elixir with Ortex
4. Integrate with VideoAnnotator application
5. Deploy to Raspberry Pi and test performance

For questions or issues, refer to the [implementation plan](implementation_plan.md).
