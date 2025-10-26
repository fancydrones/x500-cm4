import Config

# Video Annotator Configuration

# Nx Backend Selection
# By default, the backend is auto-detected based on OS:
# - macOS: EMLX.Backend (Metal GPU, 3.1x faster)
# - Linux/RPi: EXLA.Backend (CPU)
#
# You can override this for testing:
# config :video_annotator, :nx_backend, EXLA.Backend  # Force CPU
# config :video_annotator, :nx_backend, EMLX.Backend  # Force Metal (macOS only)

# Import environment-specific config
if File.exists?("#{__DIR__}/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
