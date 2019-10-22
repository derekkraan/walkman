defmodule Walkman do
  @moduledoc """
  Walkman helps you isolate your tests from the outside world.

  ## Getting started
  ```elixir
  # test/support/my_module_wrapper.ex
  require Walkman
  Walkman.def_stub(MyModuleWrapper, for: MyModule)
  ```

  ```elixir
  # config/config.exs
  config :my_app, my_module: MyModule
  ```

  ```elixir
  # config/test.exs
  config :my_app, my_module: MyModuleWrapper
  ```

  Now you can replace `MyModule` with `Application.get_env(:my_app, :my_module)` everywhere in your application code.

  ```elixir
  # test/my_module_test.exs
  test "MyModule" do
    Walkman.use_tape "MyModule1" do
      assert :ok = calls_my_module()
    end
  end
  ```

  ## Recording tapes
  The first time you run the tests, Walkman will record test fixtures. You should commit these to your git repository. To re-record your fixtures, delete them and run the tests again. Every time you run your tests after this, Walkman will use the pre-recorded tapes.

  If the implementation of a mocked module changes, any affected tests will automatically be re-recorded.

  ## Integration mode
  To disable stubs globally, use `Walkman.set_mode(:integration)`. For example:

  ```elixir
  # test/test_helper.ex
  if System.get_env("INTEGRATION_MODE"), do: Walkman.set_mode(:integration)
  ```

  ## Concurrent tests
  Concurrent tests are supported out of the box. When you use `Walkman.use_tape/3`, the tape is registered to the test process pid.

  To access the tape from another process, call `Walkman.share_tape/2`.

  Example:

  ```elixir
  test "can share tape with another process" do
    Walkman.use_tape "share_tape" do
      test_pid = self()

      spawn_link(fn ->
        Walkman.share_tape(test_pid)

        assert call_stub()
      end)
    end
  end
  ```

  If this is impractical, then making the tape global is another option. This can **not** be used with concurrent tests.

  Example:

  ```elixir
  test "can access tape globally" do
    Walkman.use_tape("global tape", global: true) do
      spawn_link(fn ->
        assert call_stub()
      end)
    end
  end
  ```
  """

  @type test_options :: [
          preserve_order: boolean(),
          global: boolean()
        ]

  defmacro def_stub(wrapper_module, for: module) do
    quote bind_quoted: [module: module, wrapper_module: wrapper_module] do
      defmodule wrapper_module do
        Enum.each(module.__info__(:functions), fn {fun, arity} ->
          args = Macro.generate_arguments(arity, module)

          def unquote(fun)(unquote_splicing(args)) do
            Walkman.call_function(unquote(module), unquote(fun), unquote(args))
          end
        end)
      end
    end
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
  @spec use_tape(tape_id :: String.t(), test_options(), do: term()) :: :ok
  defmacro use_tape(tape_id, test_options \\ [], do: block) do
    quote do
      options =
        Keyword.merge(unquote(test_options),
          mode: Walkman.mode(),
          tape_id: unquote(tape_id),
          test_pid: self()
        )

      {:ok, pid} =
        DynamicSupervisor.start_child(
          Walkman.TapeSupervisor,
          Walkman.Tape.child_spec(options)
        )

      try do
        unquote(block)
      rescue
        e ->
          :ok = GenServer.call(pid, :cancel)
          raise e
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
    :ok = Registry.put_meta(Walkman.TapeRegistry, :mode, mode)
  end

  @doc """
  Share the tape with another process.

  Example:

  ```elixir
  test "can access the stub from another process" do
    Walkman.use_tape("share tape") do
      test_pid = self()

      spawn_link(fn ->
        Walkman.share_tape(test_pid, self())
        assert call_mock()
      end)
    end
  end
  ```
  """
  def share_tape(test_pid, other_pid \\ self()) do
    {:ok, walkman_tape} = fetch_walkman_tape(test_pid)
    :ok = GenServer.call(walkman_tape, {:share_tape, other_pid})
  end

  @doc false
  def mode() do
    case Registry.meta(Walkman.TapeRegistry, :mode) do
      {:ok, :integration} ->
        :integration

      _ ->
        case walkman_tape() do
          nil ->
            :normal

          walkman_tape ->
            GenServer.call(walkman_tape, :get_replay_mode)
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

  defp record({mod, fun, args}, output) do
    :ok = GenServer.call(walkman_tape!(), {:record, {mod, fun, args}, output})
  end

  defp replay(args) do
    GenServer.call(walkman_tape!(), {:replay, args})
  end

  defp walkman_tape() do
    # Process.get("$callers") |> IO.inspect()
    [self(), :global]
    |> Enum.find_value(fn walkman_tape ->
      case fetch_walkman_tape(walkman_tape) do
        {:ok, walkman_tape} -> walkman_tape
        {:error, _err} -> false
      end
    end)
  end

  defp walkman_tape!() do
    case walkman_tape() do
      nil -> raise RuntimeError, "could not find Walkman Tape"
      walkman_tape -> walkman_tape
    end
  end

  defp fetch_walkman_tape(test_pid) do
    case Registry.lookup(Walkman.TapeRegistry, test_pid) do
      [{walkman_tape, _value}] ->
        {:ok, walkman_tape}

      [] ->
        {:error, :not_found}
    end
  end
end
