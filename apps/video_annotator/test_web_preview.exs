# Test script for webcam with web preview
# Usage: mix run test_web_preview.exs

# Don't set backend here - let Application.start() choose based on OS
# Application will use EMLX on macOS (1.8x faster) or EXLA on Linux

IO.puts """
=======================================================================
Video Annotator - Web Preview Test
=======================================================================

🌐 Web preview running at: http://localhost:4001
📊 Open in your browser to see live annotated video stream

Nx backend: #{inspect(Nx.default_backend())}

Starting detection pipeline with web preview enabled...

"""

alias VideoAnnotator.WebcamTest

# Run test with preview enabled
WebcamTest.start(
  camera: "FaceTime HD Camera",
  duration: 60,
  preview: true
)
