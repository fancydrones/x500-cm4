#!/usr/bin/env elixir

# Test to understand the detection format
model_path = "/Users/royveshovda/src/fancydrones/x500-cm4/priv/models/yolox_nano.onnx"
classes_path = "/Users/royveshovda/src/fancydrones/x500-cm4/priv/models/coco_classes.json"
image_path = "/Users/royveshovda/src/fancydrones/x500-cm4/priv/test_images/test.jpg"

# Load model
model = YOLO.load(
  model_path: model_path,
  classes_path: classes_path,
  model_impl: YOLO.Models.YOLOX
)

# Load image
image = Evision.imread(image_path)

# Run detection
detections = YOLO.detect(model, image)

IO.puts("Raw detections:")
IO.inspect(detections, limit: :infinity)

# Try to_detected_objects (swap parameters based on error)
IO.puts("\nUsing to_detected_objects:")
objects = YOLO.to_detected_objects(detections, model)
IO.inspect(objects, limit: :infinity)
