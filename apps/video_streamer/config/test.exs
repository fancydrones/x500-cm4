import Config

# Test configuration
config :video_streamer,
  env: :test,
  camera: [
    width: 640,
    height: 480,
    framerate: 15
  ],
  rtsp: [
    # Different port for testing
    port: 8555,
    path: "/test",
    enable_auth: false
  ]

# Reduce logging during tests
config :logger, level: :warning
