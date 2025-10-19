import Config

# Development-specific configuration
config :video_streamer,
  camera: [
    width: 1280,
    height: 720,
    framerate: 30
  ]

# Enable debug logging in development
config :logger, level: :debug
