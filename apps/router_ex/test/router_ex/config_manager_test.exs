defmodule RouterEx.ConfigManagerTest do
  use ExUnit.Case, async: false

  @moduletag :config_manager

  # Note: ConfigManager is a singleton GenServer that starts with the application.
  # These tests verify the INI parsing logic by testing the reload functionality.
  # Endpoints are not actually started in tests to avoid port conflicts.

  describe "INI configuration parsing - general section" do
    test "parses general section correctly" do
      ini_config = """
      [General]
      TcpServerPort=5999
      ReportStats=true
      MavlinkDialect=common
      """

      System.put_env("ROUTER_CONFIG", ini_config)
      :ok = RouterEx.ConfigManager.reload_config()

      on_exit(fn ->
        System.delete_env("ROUTER_CONFIG")
        RouterEx.ConfigManager.reload_config()
      end)

      config = RouterEx.ConfigManager.get_config()

      assert config.general[:tcp_server_port] == 5999
      assert config.general[:report_stats] == true
      assert config.general[:mavlink_dialect] == :common
    end

    test "handles comments and empty lines in general section" do
      ini_config = """
      # This is a comment
      [General]
      # Another comment
      TcpServerPort=6001

      ReportStats=false
      """

      System.put_env("ROUTER_CONFIG", ini_config)
      :ok = RouterEx.ConfigManager.reload_config()

      on_exit(fn ->
        System.delete_env("ROUTER_CONFIG")
        RouterEx.ConfigManager.reload_config()
      end)

      config = RouterEx.ConfigManager.get_config()

      assert config.general[:tcp_server_port] == 6001
      assert config.general[:report_stats] == false
    end
  end

  describe "INI configuration parsing - endpoints" do
    test "parses UDP server endpoint with message filtering" do
      ini_config = """
      [General]
      TcpServerPort=5760

      [UdpEndpoint VideoStream]
      Mode = Server
      Address = 0.0.0.0
      Port = 14560
      AllowMsgIdOut = 0,4,76,322,323
      """

      System.put_env("ROUTER_CONFIG", ini_config)
      :ok = RouterEx.ConfigManager.reload_config()

      on_exit(fn ->
        System.delete_env("ROUTER_CONFIG")
        RouterEx.ConfigManager.reload_config()
      end)

      config = RouterEx.ConfigManager.get_config()

      # Note: Endpoints list includes what was parsed, but they may not be started
      video_endpoint = Enum.find(config.endpoints, &(&1.name == "VideoStream"))

      assert video_endpoint != nil
      assert video_endpoint.type == :udp_server
      assert video_endpoint.address == "0.0.0.0"
      assert video_endpoint.port == 14560
      assert video_endpoint.allow_msg_ids == [0, 4, 76, 322, 323]
    end

    test "parses UDP client endpoint (Normal mode)" do
      ini_config = """
      [General]
      TcpServerPort=5760

      [UdpEndpoint GCS]
      Mode = Normal
      Address = 10.10.10.70
      Port = 14550
      """

      System.put_env("ROUTER_CONFIG", ini_config)
      :ok = RouterEx.ConfigManager.reload_config()

      on_exit(fn ->
        System.delete_env("ROUTER_CONFIG")
        RouterEx.ConfigManager.reload_config()
      end)

      config = RouterEx.ConfigManager.get_config()

      gcs_endpoint = Enum.find(config.endpoints, &(&1.name == "GCS"))

      assert gcs_endpoint != nil
      assert gcs_endpoint.type == :udp_client
      assert gcs_endpoint.address == "10.10.10.70"
      assert gcs_endpoint.port == 14550
    end

    test "parses multiple endpoints" do
      ini_config = """
      [General]
      TcpServerPort=5760

      [UdpEndpoint video0]
      Mode = Server
      Port = 14560
      AllowMsgIdOut = 0,4,76

      [UdpEndpoint video1]
      Mode = Server
      Port = 14561
      AllowMsgIdOut = 0,4,76

      [UdpEndpoint GCS]
      Mode = Normal
      Address = 10.10.10.70
      Port = 14550
      """

      System.put_env("ROUTER_CONFIG", ini_config)
      :ok = RouterEx.ConfigManager.reload_config()

      on_exit(fn ->
        System.delete_env("ROUTER_CONFIG")
        RouterEx.ConfigManager.reload_config()
      end)

      config = RouterEx.ConfigManager.get_config()

      assert length(config.endpoints) == 3

      assert Enum.find(config.endpoints, &(&1.name == "video0")) != nil
      assert Enum.find(config.endpoints, &(&1.name == "video1")) != nil
      assert Enum.find(config.endpoints, &(&1.name == "GCS")) != nil
    end

    test "parses BlockMsgIdOut correctly" do
      ini_config = """
      [General]
      TcpServerPort=5760

      [UdpEndpoint Filtered]
      Mode = Server
      Port = 14562
      BlockMsgIdOut = 100,200,300
      """

      System.put_env("ROUTER_CONFIG", ini_config)
      :ok = RouterEx.ConfigManager.reload_config()

      on_exit(fn ->
        System.delete_env("ROUTER_CONFIG")
        RouterEx.ConfigManager.reload_config()
      end)

      config = RouterEx.ConfigManager.get_config()

      filtered = Enum.find(config.endpoints, &(&1.name == "Filtered"))

      assert filtered != nil
      assert filtered.block_msg_ids == [100, 200, 300]
    end
  end

  describe "configuration reload" do
    test "can reload configuration dynamically" do
      # Initial config
      initial_config = """
      [General]
      TcpServerPort=6000
      """

      System.put_env("ROUTER_CONFIG", initial_config)
      :ok = RouterEx.ConfigManager.reload_config()

      config1 = RouterEx.ConfigManager.get_config()
      assert config1.general[:tcp_server_port] == 6000

      # Change config
      new_config = """
      [General]
      TcpServerPort=6001
      ReportStats=true
      """

      System.put_env("ROUTER_CONFIG", new_config)
      :ok = RouterEx.ConfigManager.reload_config()

      config2 = RouterEx.ConfigManager.get_config()
      assert config2.general[:tcp_server_port] == 6001
      assert config2.general[:report_stats] == true

      # Cleanup
      on_exit(fn ->
        System.delete_env("ROUTER_CONFIG")
        RouterEx.ConfigManager.reload_config()
      end)
    end
  end

  describe "default configuration" do
    test "uses default config when no environment variable set" do
      # Ensure no ROUTER_CONFIG
      System.delete_env("ROUTER_CONFIG")
      System.delete_env("ROUTER_CONFIG_YAML")
      System.delete_env("ROUTER_CONFIG_TOML")

      :ok = RouterEx.ConfigManager.reload_config()

      config = RouterEx.ConfigManager.get_config()

      # Should have default general settings
      assert is_list(config.general)
      assert config.general[:tcp_server_port] != nil

      # Should have endpoints from application config
      assert is_list(config.endpoints)
    end
  end
end
