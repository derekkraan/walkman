defmodule ShareTapeTest do
  use ExUnit.Case
  require Walkman

  test "can share tape with another process" do
    Walkman.use_tape "share_tape" do
      test_pid = self()

      spawn_link(fn ->
        Walkman.share_tape(test_pid, self())

        assert {:ok, "share echo"} = TestEchoWrapper.echo("share echo")
        refute_receive("share echo", 10)
        send(test_pid, :done)
      end)

      assert_receive(:done)
    end
  end
end
