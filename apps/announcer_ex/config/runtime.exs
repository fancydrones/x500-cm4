import Config

if config_env() == :prod do
  # Build router connection string from environment
  system_host = System.get_env("SYSTEM_HOST") || "router-service.rpiuav.svc.cluster.local"
  system_port = System.get_env("SYSTEM_PORT") || "14560"
  router_connection = "udpout:#{system_host}:#{system_port}"

  # Get system and component IDs
  system_id = System.get_env("SYSTEM_ID") || "1"
  camera_id = System.get_env("CAMERA_ID") || "100"

  # Configure XMAVLink with runtime values
  config :xmavlink,
    system: String.to_integer(system_id),
    component: String.to_integer(camera_id),
    connections: [router_connection]
end
