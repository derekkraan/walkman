defmodule Walkman do
  @moduledoc """
  Walkman helps you isolate your tests from the outside world.

  ## Getting started
  ```elixir
  # test/test_helper.exs
  Walkman.start_link()
  ```

  ```elixir
  # config/config.exs
  config :my_app, my_module: MyModule
  ```

  Change references to `MyModule` in your application to `Application.get_env(:my_app, :my_module)`

  ```elixir
  # config/test.exs
  config :my_app, my_module: MyModuleWrapper
  ```

  ```elixir
  # test/support/my_module_wrapper.ex
  defmodule MyModuleWrapper do
    use Walkman.Wrapper, MyModule
  end
  ```

  ```elixir
  # test/my_module_test.exs
  test "MyModule" do
    Walkman.use_tape "MyModule1" do
      assert :ok = calls_my_module()
    end
  end
  ```

  ## Recording tapes
  The first time you run the tests, Walkman will record test fixtures. You should commit these to your git repository. To re-record your fixtures, delete them and run the tests again (or put `Walkman.set_mode(:replay)` in `test/test_helper.ex`).
  """

  @doc """
  Load a tape for use in a test.

  ```elixir
  test "MyModule" do
    Walkman.use_tape "MyModule" do
      assert {:ok, _} = MyModule.my_function
    end
  end
  ```
  """
  @spec use_tape(test_id :: String.t(), do: term()) :: :ok
  defmacro use_tape(test_id, test_options \\ [], do: block) do
    quote do
      options =
        Keyword.merge(unquote(test_options),
          mode: Walkman.mode(),
          test_id: unquote(test_id),
          test_pid: self()
        )

      {:ok, pid} =
        DynamicSupervisor.start_child(
          Walkman.TestCaseSupervisor,
          Walkman.Server.child_spec(options)
        )

      try do
        unquote(block)
      rescue
        e in RuntimeError ->
          :ok = GenServer.call(pid, :cancel)
      else
        _ ->
          :ok = GenServer.call(pid, :finish)
      end
    end
  end

  @doc """
  Set Walkman's mode. The default is `:normal`.

  Walkman has two modes:

  - `:normal` - if a tape is found, then the tape is replayed. If there is no tape, then a new one is made. This is the closest to how Ruby's VCR works.
  - `:integration` - calls are passed through to the implementation but no new tapes are made. Useful for running integration tests on the CI.
  """
  @spec set_mode(mode :: :normal | :integration) :: :ok
  def set_mode(mode) when mode in [:normal, :integration] do
    :ok = Registry.put_meta(Walkman.TestCaseRegistry, :mode, mode)
  end

  def mode() do
    case Registry.meta(Walkman.TestCaseRegistry, :mode) do
      {:ok, :integration} ->
        :integration

      _ ->
        case walkman_server() do
          nil ->
            :normal

          walkman_server ->
            GenServer.call(walkman_server, :get_replay_mode)
        end
    end
  end

  @doc false
  def call_function(mod, fun, args) do
    case mode() do
      :record ->
        output = apply(mod, fun, args)
        record({mod, fun, args}, output)
        output

      :replay ->
        replay({mod, fun, args})

      :integration ->
        apply(mod, fun, args)

      :normal ->
        apply(mod, fun, args)
    end
    |> maybe_raise_error()
  end

  defmodule WalkmanError do
    defexception [:message]
  end

  defp maybe_raise_error({:walkman_error, _error} = msg) do
    raise %WalkmanError{message: msg}
  end

  defp maybe_raise_error(not_error), do: not_error

  defp record(args, output) do
    :ok = GenServer.call(walkman_server!(), {:record, args, output})
  end

  defp replay(args) do
    GenServer.call(walkman_server!(), {:replay, args})
  end

  defp walkman_server() do
    # Process.get("$callers") |> IO.inspect()
    [self(), :global]
    |> Enum.find_value(fn walkman_server ->
      case fetch_walkman_server(walkman_server) do
        {:ok, walkman_server} -> walkman_server
        {:error, _err} -> false
      end
    end)
  end

  defp walkman_server!() do
    case walkman_server() do
      nil -> raise RuntimeError, "could not find Walkman Server"
      walkman_server -> walkman_server
    end
  end

  defp fetch_walkman_server(test_pid) do
    case Registry.lookup(Walkman.TestCaseRegistry, test_pid) do
      [{walkman_server, _value}] ->
        {:ok, walkman_server}

      [] ->
        {:error, :not_found}
    end
  end
end
