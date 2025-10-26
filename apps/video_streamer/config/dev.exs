import Config

# Development-specific configuration
config :video_streamer,
  camera: [
    width: 1280,
    height: 720,
    framerate: 30,
    # Set to true for debugging camera issues
    verbose: false,
    hflip: false,
    vflip: false
  ],
  encoder: [
    profile: :main,
    level: "4.1",
    keyframe_interval: 30,
    bitrate: :auto,
    inline_headers: true,
    flush: false
  ]

# Enable debug logging in development
config :logger, level: :debug
