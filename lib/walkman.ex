defmodule Walkman do
  use GenServer

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

  @doc "Start walkman (in `test/test_helper.ex`)"
  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc false
  def child_spec(_arg), do: nil

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
  defmacro use_tape(test_id, do: block) do
    quote do
      :ok = GenServer.call(Walkman, {:set_test_id, unquote(test_id)})
      :ok = GenServer.call(Walkman, :start)
      unquote(block)
      :ok = GenServer.call(Walkman, :finish)
    end
  end

  @doc false
  def mode() do
    GenServer.call(__MODULE__, :mode)
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

      :normal ->
        apply(mod, fun, args)
    end
  end

  @doc false
  def record(args, output) do
    :ok = GenServer.call(__MODULE__, {:record, args, output})
  end

  @doc false
  def replay(args) do
    GenServer.call(__MODULE__, {:replay, args})
  end

  @doc false
  def init(_nil) do
    {:ok, {:mode_not_set, nil, []}}
  end

  @doc false
  def handle_call(:start, _from, {:normal, test_id, _tests}) do
    {:reply, :ok, {:normal, test_id, []}}
  end

  def handle_call(:start, _from, {_mode, test_id, _tests}) do
    case load_replay(test_id) do
      {:ok, tests} ->
        {:reply, :ok, {:replay, test_id, tests}}

      {:error, _err} ->
        {:reply, :ok, {:record, test_id, []}}
    end
  end

  def handle_call(:finish, _from, {:record, test_id, tests}) do
    save_replay(test_id, tests)
    {:reply, :ok, {:record, test_id, []}}
  end

  def handle_call(:finish, _from, {mode, test_id, _tests}) do
    {:reply, :ok, {mode, test_id, []}}
  end

  def handle_call({:record, args, output}, _from, {mode, test_id, tests}) do
    {:reply, :ok, {mode, test_id, [{args, output} | tests]}}
  end

  def handle_call({:replay, args}, _from, {_mode, _test_id, tests} = state) do
    {_key, value} =
      Enum.find(tests, :module_test_not_found, fn
        {replay_args, _output} -> replay_args == args
      end)
      |> case do
        :module_test_not_found -> raise "replay not found for args #{inspect(args)}"
        other -> other
      end

    {:reply, value, state}
  end

  def handle_call({:set_mode, mode}, _from, {_mode, test_id, _tests})
      when mode in [:record, :replay, :normal] do
    {:reply, :ok, {mode, test_id, []}}
  end

  def handle_call(:mode, _from, {mode, _, _} = state) do
    {:reply, mode, state}
  end

  def handle_call({:set_test_id, test_id}, _from, {mode, _test_id, _tests}) do
    {:reply, :ok, {mode, test_id, []}}
  end

  defp filename(test_id) do
    Path.relative_to("test/fixtures/walkman/#{test_id}", File.cwd!())
  end

  defp load_replay(test_id) do
    case File.read(filename(test_id)) do
      {:ok, contents} -> {:ok, :erlang.binary_to_term(contents)}
      {:error, err} -> {:error, err}
    end
  end

  defp save_replay(test_id, tests) do
    Path.relative_to("test/fixtures/walkman", File.cwd!()) |> File.mkdir_p()
    filename(test_id) |> File.write!(:erlang.term_to_binary(tests), [:write])
  end
end
