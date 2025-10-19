import Config

# Test configuration
config :video_streamer,
  camera: [
    width: 640,
    height: 480,
    framerate: 15
  ],
  rtsp: [
    port: 8555,  # Different port for testing
    path: "/test",
    enable_auth: false
  ]

# Reduce logging during tests
config :logger, level: :warning
