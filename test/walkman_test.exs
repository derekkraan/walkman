defmodule WalkmanTest do
  use ExUnit.Case
  doctest Walkman

  test "uses a pre-recorded tape" do
    Walkman.use_tape "echo" do
      assert :ok = TestEchoWrapper.echo("echo")
      refute_receive("echo", 10)
    end
  end
end
