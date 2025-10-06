defmodule AnnouncerExTest do
  use ExUnit.Case
  doctest AnnouncerEx

  test "greets the world" do
    assert AnnouncerEx.hello() == :world
  end
end
