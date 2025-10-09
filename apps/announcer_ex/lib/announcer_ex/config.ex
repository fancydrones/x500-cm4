defmodule AnnouncerEx.Config do
  @moduledoc """
  Configuration management for the announcer application.
  Reads configuration from application environment.
  """

  @doc """
  Get the camera URL from application config.
  Raises if not set.
  """
  def camera_url! do
    Application.fetch_env!(:announcer_ex, :camera_url) ||
      raise "camera_url configuration is required"
  end

  @doc """
  Get the camera component ID from application config.
  Raises if not set.
  """
  def camera_id! do
    Application.fetch_env!(:announcer_ex, :camera_id)
  end

  @doc """
  Get the camera name from application config.
  Raises if not set.
  """
  def camera_name! do
    Application.fetch_env!(:announcer_ex, :camera_name) ||
      raise "camera_name configuration is required"
  end

  @doc """
  Get the MAVLink system host from application config.
  Defaults to router service hostname.
  """
  def system_host! do
    Application.get_env(:announcer_ex, :system_host, "router-service.rpiuav.svc.cluster.local")
  end

  @doc """
  Get the MAVLink system port from application config.
  Defaults to 14560.
  """
  def system_port! do
    Application.get_env(:announcer_ex, :system_port, 14560)
  end

  @doc """
  Get the MAVLink system ID from application config.
  Defaults to 1.
  """
  def system_id! do
    Application.get_env(:announcer_ex, :system_id, 1)
  end

  @doc """
  Build the router connection string.
  Returns a string like "udpout:host:port"
  """
  def router_connection_string! do
    "udpout:#{system_host!()}:#{system_port!()}"
  end

  @doc """
  Get whether to enable periodic stream status broadcasting.
  Defaults to false (disabled).
  """
  def enable_stream_status! do
    Application.get_env(:announcer_ex, :enable_stream_status, false)
  end

  @doc """
  Get whether to enable periodic camera info broadcasting.
  Some QGC versions require cameras to periodically announce themselves.
  Defaults to true (enabled).
  """
  def enable_camera_info_broadcast! do
    Application.get_env(:announcer_ex, :enable_camera_info_broadcast, true)
  end
end
