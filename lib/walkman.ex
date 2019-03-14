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

  @doc false
  def child_spec(_) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  @doc false
  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(WalkmanServer, nil, name: __MODULE__)
  end

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
      :ok = GenServer.call(Walkman, {:set_test_id, unquote(test_id), unquote(test_options)})
      :ok = GenServer.call(Walkman, :start)
      unquote(block)
      :ok = GenServer.call(Walkman, :finish)
    end
  end

  @doc """
  Set Walkman's mode. The default is `:normal`.

  Walkman has three modes:

  - `:normal` - if a tape is found, then the tape is replayed. If there is no tape, then a new one is made. This is the closest to how Ruby's VCR works.
  - `:replay` - only replay, and raise an exception if no pre-recorded tape is found. This should be used when running the tests on the CI.
  - `:record` - all calls are passed through to the implementation and record new tapes. This can be used to re-record tapes.
  - `:integration` - calls are passed through to the implementation but no new tapes are made. Useful for running integration tests on the CI.
  """
  @spec set_mode(mode :: :normal | :replay | :record) :: :ok
  def set_mode(mode) when mode in [:normal, :replay, :record] do
    :ok = GenServer.call(__MODULE__, {:set_mode, mode})
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

  defp maybe_raise_error({:error, error}) do
    raise error
  end

  defp maybe_raise_error(not_error), do: not_error

  defp mode() do
    GenServer.call(__MODULE__, :mode)
  end

  defp record(args, output) do
    :ok = GenServer.call(__MODULE__, {:record, args, output})
  end

  defp replay(args) do
    GenServer.call(__MODULE__, {:replay, args})
  end
end
