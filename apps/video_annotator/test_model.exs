#!/usr/bin/env elixir

# Simple script to test YOLOX model loading
IO.puts("Testing YOLOX model loading...")

model_path = "/Users/royveshovda/src/fancydrones/x500-cm4/priv/models/yolox_nano.onnx"
classes_path = "/Users/royveshovda/src/fancydrones/x500-cm4/priv/models/coco_classes.json"

IO.puts("Model path: #{model_path}")
IO.puts("Classes path: #{classes_path}")
IO.puts("Model exists: #{File.exists?(model_path)}")
IO.puts("Classes exist: #{File.exists?(classes_path)}")

IO.puts("\nAttempting to load model...")

try do
  model = YOLO.load(
    model_path: model_path,
    classes_path: classes_path,
    model_impl: YOLO.Models.YOLOX
  )

  IO.puts("SUCCESS! Model loaded:")
  IO.inspect(model)
rescue
  error ->
    IO.puts("ERROR loading model:")
    IO.inspect(error)
    IO.puts("\nStacktrace:")
    IO.inspect(__STACKTRACE__)
end
