defmodule WalkmanTest do
  use ExUnit.Case
  doctest Walkman

  test "without tape" do
    assert {:ok, "echo"} = TestEchoWrapper.echo("echo")
    assert_receive("echo", 10)
  end

  test "uses a pre-recorded tape" do
    Walkman.use_tape "echo" do
      assert {:ok, "echo"} = TestEchoWrapper.echo("echo")
      refute_receive("echo", 10)
    end
  end

  test "works in integration mode" do
    Walkman.set_mode(:integration)

    Walkman.use_tape "integration mode" do
      assert {:ok, "integration"} = TestEchoWrapper.echo("integration")
      assert_receive("integration", 10)
    end

    Walkman.set_mode(:normal)
  end

  test "records a fixture" do
    File.rm("test/fixtures/walkman/record a fixture")
    refute File.exists?("test/fixtures/walkman/record a fixture")

    Walkman.use_tape "record a fixture" do
      assert {:ok, "record a fixture"} = TestEchoWrapper.echo("record a fixture")
    end

    assert File.exists?("test/fixtures/walkman/record a fixture")
  end

  test "does not record a fixture when the test fails" do
    assert_raise(MatchError, fn ->
      Walkman.use_tape "no_fixture" do
        :does_not_match = TestEchoWrapper.echo("do not record this")
      end
    end)

    refute File.exists?("test/fixtures/walkman/no_fixture")
  end
end
