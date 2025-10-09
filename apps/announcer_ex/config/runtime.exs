import Config

# This configuration runs at runtime (when the release starts)

# Parse integer from environment variable with validation
parse_int = fn env_var, default ->
  case System.get_env(env_var) do
    nil ->
      default

    value ->
      case Integer.parse(value) do
        {id, ""} -> id
        _ -> raise "#{env_var} must be a valid integer, got: #{value}"
      end
  end
end

# Parse boolean from environment variable
parse_bool = fn env_var, default ->
  case System.get_env(env_var) do
    nil -> default
    "true" -> true
    "1" -> true
    "false" -> false
    "0" -> false
    _ -> default
  end
end

# Network configuration
system_host = System.get_env("SYSTEM_HOST") || "router-service.rpiuav.svc.cluster.local"
system_port = parse_int.("SYSTEM_PORT", 14560)
system_id = parse_int.("SYSTEM_ID", 1)

# Camera configuration
camera_id = parse_int.("CAMERA_ID", 100)

camera_name =
  System.get_env("CAMERA_NAME") || raise "CAMERA_NAME environment variable is required"

camera_url = System.get_env("CAMERA_URL") || raise "CAMERA_URL environment variable is required"

# Feature flags
enable_stream_status = parse_bool.("ENABLE_STREAM_STATUS", false)
enable_camera_info_broadcast = parse_bool.("ENABLE_CAMERA_INFO_BROADCAST", true)

# Build router connection string
router_connection = "udpout:#{system_host}:#{system_port}"

# Configure XMAVLink with runtime values
config :xmavlink,
  system_id: system_id,
  component_id: camera_id,
  connections: [router_connection]

# Configure AnnouncerEx with runtime values
config :announcer_ex,
  camera_id: camera_id,
  camera_name: camera_name,
  camera_url: camera_url,
  system_id: system_id,
  enable_stream_status: enable_stream_status,
  enable_camera_info_broadcast: enable_camera_info_broadcast
