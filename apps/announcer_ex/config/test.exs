import Config

# Test-specific config - configure announcer_ex for tests
config :announcer_ex,
  camera_id: 100,
  camera_name: "Test Camera",
  camera_url: "rtsp://test:554/stream",
  system_id: 1,
  system_host: "localhost",
  system_port: 14550,
  enable_stream_status: false,
  enable_camera_info_broadcast: true
