defmodule ConcurrencyTest do
  use ExUnit.Case
  require Walkman

  test "concurrent tapes work" do
    # The timings in this test ensures that Walkman has tape_1 active while `t2` tries to do its assertion.
    # The tapes were recorded without sleeps.

    t1 =
      Task.async(fn ->
        Process.sleep(100)

        Walkman.use_tape "tape_1" do
          Process.sleep(100)
          assert {:ok, "echo1"} = TestEchoWrapper.echo("echo1")
        end
      end)

    t2 =
      Task.async(fn ->
        Walkman.use_tape "tape_2" do
          Process.sleep(150)
          assert {:ok, "echo2"} = TestEchoWrapper.echo("echo2")
        end
      end)

    Task.await(t1)
    Task.await(t2)
  end
end
