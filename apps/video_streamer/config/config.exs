import Config

# Development/test defaults
config :video_streamer,
  camera: [
    width: 1920,
    height: 1080,
    framerate: 30,
    # Set to true to see frame statistics from rpicam-vid
    verbose: false
  ],
  rtsp: [
    port: 8554,
    path: "/video",
    enable_auth: false
  ],
  encoder: [
    profile: :baseline,
    # Every 1 second at 30fps
    keyframe_interval: 30
  ]

# Import environment-specific config
import_config "#{config_env()}.exs"
