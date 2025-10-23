defmodule RouterExTest do
  use ExUnit.Case
  doctest RouterEx

  test "greets the world" do
    assert RouterEx.hello() == :world
  end
end
