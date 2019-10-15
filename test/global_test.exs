defmodule GlobalTest do
  use ExUnit.Case
  require Walkman

  test "global test" do
    Walkman.use_tape "global test", global: true do
      test_pid = self()

      spawn_link(fn ->
        assert {:ok, "global echo"} = TestEchoWrapper.echo("global echo")
        refute_receive("global echo", 10)
        send(test_pid, :done)
      end)

      assert_receive(:done)
    end
  end

  test "can set global as default" do
    Application.put_env(:walkman, :global, true)

    Walkman.use_tape "global test" do
      test_pid = self()

      spawn_link(fn ->
        assert {:ok, "global echo"} = TestEchoWrapper.echo("global echo")
        refute_receive("global echo", 10)
        send(test_pid, :done)
      end)

      assert_receive(:done)
    end

    Application.put_env(:walkman, :global, false)
  end
end
