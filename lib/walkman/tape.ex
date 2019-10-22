defmodule Walkman.Tape do
  use GenServer

  @moduledoc false

  defstruct mode: :normal,
            replay_mode: nil,
            tape_id: nil,
            tests: [],
            preserve_order: true,
            module_md5s: %{}

  @type mode :: :normal | :integration

  @type replay_mode :: :replay | :record

  @type tape_id :: String.t()

  @type options :: [
          tape_id: tape_id(),
          mode: mode(),
          test_pid: pid(),
          global: boolean(),
          preserve_order: boolean()
        ]

  @spec child_spec(options) :: Supervisor.child_spec()
  def child_spec(options) do
    %{start: {__MODULE__, :start_link, [options]}, id: nil, restart: :transient}
  end

  @spec start_link(options) :: {:ok, pid} | {:error, term()}
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  defp register_tape(true, _test_pid) do
    {:ok, _pid} = Registry.register(Walkman.TapeRegistry, :global, nil)
  end

  defp register_tape(false, test_pid) when is_pid(test_pid) do
    {:ok, _pid} = Registry.register(Walkman.TapeRegistry, test_pid, nil)
  end

  def init(options) do
    mode = Keyword.get(options, :mode, :normal)
    tape_id = Keyword.fetch!(options, :tape_id)
    test_pid = Keyword.fetch!(options, :test_pid)
    preserve_order = Keyword.get(options, :preserve_order, true)
    global = Keyword.get(options, :global, Application.get_env(:walkman, :global, false))

    register_tape(global, test_pid)

    state =
      %__MODULE__{mode: mode, tape_id: tape_id, preserve_order: preserve_order}
      |> init_tests()

    {:ok, state}
  end

  defp init_tests(%{mode: :integration} = s) do
    %{s | tests: []}
  end

  defp init_tests(s) do
    case load_replay(s) do
      {:ok, new_state} ->
        %{new_state | replay_mode: :replay}
        |> check_module_md5s()

      {:error, _err} ->
        %{s | replay_mode: :record, tests: []}
    end
  end

  # change to record mode if any of the module md5s don't match
  defp check_module_md5s(state) do
    Enum.all?(state.module_md5s, fn {module, md5} ->
      md5 == module.__info__(:md5)
    end)
    |> case do
      true -> state
      false -> %{state | replay_mode: :record, tests: [], module_md5s: %{}}
    end
  end

  def handle_call({:share_tape, pid}, _from, state) do
    Registry.register(Walkman.TapeRegistry, pid, nil)
    {:reply, :ok, state}
  end

  def handle_call(:get_replay_mode, _from, %{replay_mode: replay_mode} = s) do
    {:reply, replay_mode, s}
  end

  def handle_call({:record, {mod, _, _} = mfa, output}, _from, s) do
    s =
      Map.put(s, :module_md5s, Map.put(s.module_md5s, mod, mod.__info__(:md5)))
      |> Map.put(:tests, [{mfa, output} | s.tests])

    {:reply, :ok, s}
  end

  def handle_call({:replay, mfa}, _from, s) do
    case s.preserve_order do
      true ->
        # only match on first test, then discard it to preserve order
        case s.tests do
          [] ->
            {:reply, {:walkman_error, "there are no more calls left to replay"}, s}

          [{replay_args, value} | tests] ->
            if args_match?(replay_args, mfa) do
              {:reply, value, %{s | tests: tests}}
            else
              {:reply,
               {:walkman_error,
                "replay found #{inspect(replay_args)} didn't match given mfa #{inspect(mfa)}"}, s}
            end
        end

      false ->
        Enum.find(s.tests, :module_test_not_found, fn
          {replay_args, _output} -> args_match?(replay_args, mfa)
        end)
        |> case do
          :module_test_not_found ->
            {:reply, {:walkman_error, "replay not found for mfa #{inspect(mfa)}"}, s}

          {_key, value} ->
            {:reply, value, s}
        end
    end
  end

  def handle_call(:finish, _from, %{replay_mode: :record} = state) do
    save_replay(state)
    {:stop, :normal, :ok, nil}
  end

  def handle_call(:finish, _from, _s) do
    {:stop, :normal, :ok, nil}
  end

  def handle_call(:cancel, _from, _s) do
    {:stop, :normal, :ok, nil}
  end

  defp filename(tape_id) do
    Path.relative_to("test/fixtures/walkman/#{tape_id}", File.cwd!())
  end

  defp load_replay(state) do
    case File.read(filename(state.tape_id)) do
      {:ok, contents} ->
        {:ok, Map.merge(state, decode_state(contents))}

      {:error, err} ->
        {:error, err}
    end
  end

  defp save_replay(state) do
    File.write!(filename(state.tape_id), encode_state(state), [
      :write
    ])
  end

  defp encode_state(state) do
    :erlang.term_to_binary({Enum.reverse(state.tests), state.module_md5s})
  end

  defp decode_state(string) do
    {tests, module_md5s} = :erlang.binary_to_term(string)
    %{tests: tests, module_md5s: module_md5s}
  end

  defp args_match?(args, args2) do
    normalize_args(args) == normalize_args(args2)
  end

  defp normalize_args(arg) when is_list(arg),
    do: Enum.map(arg, fn arg -> normalize_args(arg) end)

  defp normalize_args(%Regex{} = arg), do: Regex.recompile!(arg)
  defp normalize_args(%_struct{} = arg), do: arg

  defp normalize_args(arg) when is_map(arg),
    do: arg |> Enum.map(fn {k, v} -> {normalize_args(k), normalize_args(v)} end) |> Enum.into(%{})

  defp normalize_args(arg) when is_tuple(arg),
    do: arg |> Tuple.to_list() |> normalize_args |> List.to_tuple()

  defp normalize_args(arg), do: arg
end
