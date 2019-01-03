defmodule Walkman do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def set_mode(mode) do
    :ok = GenServer.call(__MODULE__, {:set_mode, mode})
  end

  def mode() do
    GenServer.call(__MODULE__, :mode)
  end

  defmacro use_tape(test_id, do: block) do
    quote do
      :ok = GenServer.call(Walkman, {:set_test_id, unquote(test_id)})
      :ok = GenServer.call(Walkman, :start)
      unquote(block)
      :ok = GenServer.call(Walkman, :finish)
    end
  end

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
    end
  end

  def record(args, output) do
    :ok = GenServer.call(__MODULE__, {:record, args, output})
  end

  def replay(args) do
    GenServer.call(__MODULE__, {:replay, args})
  end

  def init(_nil) do
    {:ok, {:mode_not_set, nil, []}}
  end

  def handle_call(:start, _from, {:integration, test_id, _tests}) do
    {:reply, :ok, {:integration, test_id, []}}
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
      when mode in [:record, :replay, :integration] do
    {:reply, :ok, {mode, test_id, []}}
  end

  def handle_call({:set_mode, mode}, _from, {_mode, test_id, _tests})
      when mode in ["record", "replay", "integration"] do
    {:reply, :ok, {String.to_atom(mode), test_id, []}}
  end

  def handle_call(:mode, _from, {mode, _, _} = state) do
    {:reply, mode, state}
  end

  def handle_call({:set_test_id, test_id}, _from, {mode, _test_id, _tests}) do
    {:reply, :ok, {mode, test_id, []}}
  end

  defp filename(test_id),
    do: Path.relative_to("test/fixtures/walkman/#{test_id}", File.cwd!())

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
