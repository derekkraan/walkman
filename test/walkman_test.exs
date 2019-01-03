defmodule WalkmanTest do
  use ExUnit.Case
  doctest Walkman

  test "greets the world" do
    assert Walkman.hello() == :world
  end
end
