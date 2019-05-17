defmodule WalkmanTest do
  use ExUnit.Case
  doctest Walkman

  test "without tape" do
    assert :ok = TestEchoWrapper.echo("echo")
    assert_receive("echo", 10)
  end

  test "uses a pre-recorded tape" do
    Walkman.use_tape "echo" do
      assert :ok = TestEchoWrapper.echo("echo")
      refute_receive("echo", 10)
    end
  end

  test "works in integration mode" do
    Walkman.set_mode(:integration)

    Walkman.use_tape "integration mode" do
      assert :ok = TestEchoWrapper.echo("integration")
      assert_receive("integration", 10)
    end

    Walkman.set_mode(:normal)
  end
end
