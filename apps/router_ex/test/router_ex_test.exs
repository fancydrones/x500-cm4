defmodule RouterExTest do
  use ExUnit.Case
  doctest RouterEx

  test "application module is defined" do
    assert Code.ensure_loaded?(RouterEx)
  end

  test "health_check returns ok when RouterCore is running" do
    # RouterCore is already started by the application
    assert {:ok, _health} = RouterEx.health_check()
  end

  test "version returns current version" do
    version = RouterEx.version()
    assert is_binary(version)
    assert version =~ ~r/\d+\.\d+\.\d+/
  end
end
