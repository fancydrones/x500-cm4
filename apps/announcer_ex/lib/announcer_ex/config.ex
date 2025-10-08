defmodule AnnouncerEx.Config do
  @moduledoc """
  Configuration management for the announcer application.
  Reads and validates environment variables.
  """

  @doc """
  Get the camera URL from environment.
  Raises if not set.
  """
  def camera_url! do
    System.get_env("CAMERA_URL") ||
      raise "CAMERA_URL environment variable is required"
  end

  @doc """
  Get the camera component ID from environment.
  Raises if not set or invalid integer.
  """
  def camera_id! do
    case System.get_env("CAMERA_ID") do
      nil ->
        raise "CAMERA_ID environment variable is required"

      value ->
        case Integer.parse(value) do
          {id, ""} -> id
          _ -> raise "CAMERA_ID must be a valid integer, got: #{value}"
        end
    end
  end

  @doc """
  Get the camera name from environment.
  Raises if not set.
  """
  def camera_name! do
    System.get_env("CAMERA_NAME") ||
      raise "CAMERA_NAME environment variable is required"
  end

  @doc """
  Get the MAVLink system host from environment.
  Defaults to router service hostname.
  """
  def system_host! do
    System.get_env("SYSTEM_HOST") || "router-service.rpiuav.svc.cluster.local"
  end

  @doc """
  Get the MAVLink system port from environment.
  Defaults to 14560.
  """
  def system_port! do
    case System.get_env("SYSTEM_PORT") do
      nil ->
        14560

      value ->
        case Integer.parse(value) do
          {port, ""} -> port
          _ -> raise "SYSTEM_PORT must be a valid integer, got: #{value}"
        end
    end
  end

  @doc """
  Get the MAVLink system ID from environment.
  Defaults to 1.
  """
  def system_id! do
    case System.get_env("SYSTEM_ID") do
      nil ->
        1

      value ->
        case Integer.parse(value) do
          {id, ""} -> id
          _ -> raise "SYSTEM_ID must be a valid integer, got: #{value}"
        end
    end
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
    case System.get_env("ENABLE_STREAM_STATUS") do
      nil -> false
      "true" -> true
      "1" -> true
      _ -> false
    end
  end

  @doc """
  Get whether to enable periodic camera info broadcasting.
  Some QGC versions require cameras to periodically announce themselves.
  Defaults to true (enabled).
  """
  def enable_camera_info_broadcast! do
    case System.get_env("ENABLE_CAMERA_INFO_BROADCAST") do
      nil -> true
      "true" -> true
      "1" -> true
      "false" -> false
      "0" -> false
      _ -> true
    end
  end
end
