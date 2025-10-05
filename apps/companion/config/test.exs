import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :companion, CompanionWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "uUOuVnovvsJpNmbSsYAunxCwdx1oiRKaTX+A26+2vmc9lW23SXRa03c4hJsjO/Yk",
  server: false

config :companion,
  use_file: true,
  file_path: "~/k3s.yaml",
  # Use this to develop locally without constrains to k8s
  k8s_api_manager: Companion.SimulatedK8sApiManager

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Uncomment if needed for MAVLink testing
# config :mavlink, dialect: Common
