defmodule AnnouncerEx.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Ensure XMAVLink application is started
    Application.ensure_all_started(:xmavlink)

    # Log XMAVLink configuration for debugging
    xmavlink_config = Application.get_all_env(:xmavlink)
    Logger.debug("XMAVLink configuration: #{inspect(xmavlink_config)}")

    children = [
      AnnouncerEx.CameraManager
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AnnouncerEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
