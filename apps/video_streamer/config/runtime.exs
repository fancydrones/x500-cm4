import Config

# Runtime configuration from environment variables
if config_env() == :prod do
  config :video_streamer,
    camera: [
      width: System.get_env("STREAM_WIDTH", "1920") |> String.to_integer(),
      height: System.get_env("STREAM_HEIGHT", "1080") |> String.to_integer(),
      framerate: System.get_env("STREAM_FPS", "30") |> String.to_integer(),
      hflip: System.get_env("CAMERA_HFLIP", "false") == "true",
      vflip: System.get_env("CAMERA_VFLIP", "false") == "true"
    ],
    rtsp: [
      port: System.get_env("RTSP_PORT", "8554") |> String.to_integer(),
      path: System.get_env("RTSP_PATH", "/video"),
      enable_auth: System.get_env("RTSP_AUTH", "false") == "true",
      username: System.get_env("RTSP_USERNAME"),
      password: System.get_env("RTSP_PASSWORD")
    ],
    encoder: [
      profile: System.get_env("H264_PROFILE", "main") |> String.to_atom(),
      level: System.get_env("H264_LEVEL", "4.1"),
      keyframe_interval: System.get_env("KEYFRAME_INTERVAL", "30") |> String.to_integer(),
      bitrate: (case System.get_env("H264_BITRATE") do
        nil -> :auto
        "auto" -> :auto
        bitrate_str -> String.to_integer(bitrate_str)
      end),
      inline_headers: System.get_env("H264_INLINE_HEADERS", "true") == "true",
      flush: System.get_env("H264_FLUSH", "false") == "true"
    ]
end
