import Config

# Configure XMAVLink dialect
config :xmavlink,
  dialect: Common

# Import environment-specific config
import_config "#{config_env()}.exs"
