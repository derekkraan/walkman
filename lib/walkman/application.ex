defmodule Walkman.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [Walkman]
    opts = [strategy: :one_for_one, name: Walkman.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
