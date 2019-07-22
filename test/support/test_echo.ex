defmodule TestEcho do
  def echo(msg) do
    send(self(), msg)
    {:ok, msg}
  end
end

require Walkman

Walkman.def_stub(TestEchoWrapper, for: TestEcho)
