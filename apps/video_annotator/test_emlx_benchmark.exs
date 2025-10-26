# EMLX vs EXLA Benchmark Test
# Compares Metal GPU acceleration vs CPU for YOLOX inference

IO.puts """
=======================================================================
EMLX vs EXLA Performance Benchmark
=======================================================================

Testing YOLOX-Nano inference with:
1. EXLA Backend (CPU)
2. EMLX Backend (Metal GPU)

This will help determine if Metal acceleration provides significant
speedup for inference on macOS.
=======================================================================
"""

defmodule BenchmarkHelpers do
  def load_test_image do
    # Create a dummy 640x640 RGB image (simulating camera input)
    # Create binary buffer: 640 * 640 * 3 bytes (all zeros)
    binary = :binary.copy(<<0>>, 640 * 640 * 3)

    # Create Evision Mat from binary (same format as camera output)
    Evision.Mat.from_binary(binary, :u8, 640, 640, 3)
  end

  def benchmark_backend(backend_name, backend_module, model_path, classes_path, image, iterations \\ 50) do
    IO.puts "\n--- Testing #{backend_name} ---"

    # Set backend BEFORE loading model
    previous = Nx.default_backend()
    Nx.global_default_backend(backend_module)

    # Load model with this backend
    IO.puts "Loading model with #{backend_name}..."
    model = YOLO.load(
      model_path: model_path,
      classes_path: classes_path,
      model_impl: YOLO.Models.YOLOX
    )

    # Warmup (5 runs)
    IO.puts "Warmup (5 iterations)..."
    Enum.each(1..5, fn _ ->
      YOLO.detect(model, image)
    end)

    # Benchmark
    IO.puts "Benchmarking (#{iterations} iterations)..."
    times = Enum.map(1..iterations, fn i ->
      start = System.monotonic_time(:millisecond)
      _detections = YOLO.detect(model, image)
      elapsed = System.monotonic_time(:millisecond) - start

      if rem(i, 10) == 0 do
        IO.write(".")
      end

      elapsed
    end)

    IO.puts "\n"

    # Calculate statistics
    avg_time = Enum.sum(times) / length(times)
    min_time = Enum.min(times)
    max_time = Enum.max(times)
    median_time = Enum.at(Enum.sort(times), div(length(times), 2))

    # Restore previous backend
    Nx.global_default_backend(previous)

    %{
      backend: backend_name,
      avg: avg_time,
      min: min_time,
      max: max_time,
      median: median_time,
      fps: 1000.0 / avg_time
    }
  end

  def print_results(results) do
    IO.puts """

    =======================================================================
    BENCHMARK RESULTS
    =======================================================================
    """

    Enum.each(results, fn result ->
      IO.puts """
      #{result.backend}:
        Average: #{:erlang.float_to_binary(result.avg * 1.0, [decimals: 1])}ms
        Median:  #{:erlang.float_to_binary(result.median * 1.0, [decimals: 1])}ms
        Min:     #{result.min}ms
        Max:     #{result.max}ms
        FPS:     #{:erlang.float_to_binary(result.fps * 1.0, [decimals: 2])}
      """
    end)

    # Calculate speedup
    if length(results) == 2 do
      [exla, emlx] = results
      speedup = exla.avg / emlx.avg
      percent_faster = (speedup - 1.0) * 100.0

      IO.puts """
      =======================================================================
      SPEEDUP ANALYSIS
      =======================================================================

      EMLX is #{:erlang.float_to_binary(speedup * 1.0, [decimals: 2])}x faster than EXLA
      (#{:erlang.float_to_binary(percent_faster * 1.0, [decimals: 1])}% improvement)

      FPS improvement: #{:erlang.float_to_binary(exla.fps * 1.0, [decimals: 2])} → #{:erlang.float_to_binary(emlx.fps * 1.0, [decimals: 2])}
      """

      # Recommendation
      if speedup > 1.5 do
        IO.puts """
        ✅ RECOMMENDATION: Use EMLX for macOS development

        Metal GPU acceleration provides significant speedup (>50%).
        This will improve development workflow and testing.

        NOTE: EMLX is macOS-only. For Raspberry Pi deployment,
        continue using EXLA (CPU) backend.
        """
      else
        IO.puts """
        ⚠️  RECOMMENDATION: Stick with EXLA

        Speedup is minimal (<50%). EXLA is more portable and
        the performance difference doesn't justify the added dependency.
        """
      end
    end

    IO.puts "======================================================================="
  end
end

# Main benchmark
try do
  model_path = "priv/models/yolox_nano.onnx"
  classes_path = "priv/models/coco_classes.json"

  # Load test image
  IO.puts "Creating test image (640x640)..."
  image = BenchmarkHelpers.load_test_image()
  IO.puts "✓ Test image ready"

  # Run benchmarks
  # Each backend loads the model independently to avoid tensor mismatch
  results = [
    BenchmarkHelpers.benchmark_backend("EXLA (CPU)", EXLA.Backend, model_path, classes_path, image),
    BenchmarkHelpers.benchmark_backend("EMLX (Metal GPU)", EMLX.Backend, model_path, classes_path, image)
  ]

  # Print results
  BenchmarkHelpers.print_results(results)

rescue
  e ->
    IO.puts "\n❌ Error during benchmark: #{inspect(e)}"
    IO.puts "\nStacktrace:"
    IO.puts Exception.format_stacktrace(__STACKTRACE__)
end
