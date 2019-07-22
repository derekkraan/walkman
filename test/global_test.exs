defmodule GlobalTest do
  use ExUnit.Case
  require Walkman

  test "global test" do
    Walkman.use_tape "global test", global: true do
      test_pid = self()

      spawn_link(fn ->
        assert {:ok, "global echo"} = TestEchoWrapper.echo("global echo")
        send(test_pid, :done)
      end)

      assert_receive(:done)
    end
  end
end
