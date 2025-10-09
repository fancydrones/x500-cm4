import Config

# This configuration runs at runtime (when the release starts)
# Build router connection string from environment
system_host = System.get_env("SYSTEM_HOST") || "router-service.rpiuav.svc.cluster.local"
system_port = System.get_env("SYSTEM_PORT") || "14560"
router_connection = "udpout:#{system_host}:#{system_port}"

# Get system and component IDs
system_id = System.get_env("SYSTEM_ID") || "1"
camera_id = System.get_env("CAMERA_ID") || "100"

# Configure XMAVLink with runtime values
# Note: XMAVLink.Supervisor expects :system_id and :component_id (not :system and :component)
config :xmavlink,
  system_id: String.to_integer(system_id),
  component_id: String.to_integer(camera_id),
  connections: [router_connection]

# Configure announcer_ex with runtime values from environment variables
config :announcer_ex,
  camera_url: System.get_env("CAMERA_URL"),
  camera_id: String.to_integer(camera_id),
  camera_name: System.get_env("CAMERA_NAME"),
  system_host: system_host,
  system_port: String.to_integer(system_port),
  system_id: String.to_integer(system_id),
  enable_stream_status: System.get_env("ENABLE_STREAM_STATUS") in ["true", "1"],
  enable_camera_info_broadcast:
    case System.get_env("ENABLE_CAMERA_INFO_BROADCAST") do
      "false" -> false
      "0" -> false
      _ -> true
    end
