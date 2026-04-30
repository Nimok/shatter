defmodule ShatterTest do
  use ExUnit.Case
  doctest Shatter

  test "greets the world" do
    assert Shatter.hello() == :world
  end
end
