defmodule AllowanceTest do
  use ExUnit.Case
  require Walkman

  test "can allow another process access to our walkman tape" do
    Walkman.use_tape "allowance" do
      test_pid = self()

      spawn_link(fn ->
        Walkman.share_tape(test_pid, self())

        assert {:ok, "allowance echo"} = TestEchoWrapper.echo("allowance echo")
        refute_receive("allowance echo", 10)
        send(test_pid, :done)
      end)

      assert_receive(:done)
    end
  end
end
