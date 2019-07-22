defmodule Walkman.Tape do
  use GenServer

  @moduledoc false

  defstruct mode: :normal, replay_mode: nil, tape_id: nil, tests: [], preserve_order: true

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

  def init(options) do
    mode = Keyword.get(options, :mode, :normal)
    tape_id = Keyword.fetch!(options, :tape_id)
    test_pid = Keyword.fetch!(options, :test_pid)
    preserve_order = Keyword.get(options, :preserve_order, true)
    global = Keyword.get(options, :global, false)

    if global do
      Registry.register(Walkman.TapeRegistry, :global, nil)
    else
      Registry.register(Walkman.TapeRegistry, test_pid, nil)
    end

    state =
      %__MODULE__{mode: mode, tape_id: tape_id, preserve_order: preserve_order}
      |> init_tests()

    {:ok, state}
  end

  defp init_tests(%{mode: :integration} = s) do
    %{s | tests: []}
  end

  defp init_tests(s) do
    case load_replay(s.tape_id) do
      {:ok, tests} ->
        %{s | replay_mode: :replay, tests: tests}

      {:error, _err} ->
        %{s | replay_mode: :record, tests: []}
    end
  end

  def handle_call({:share_tape, pid}, _from, state) do
    Registry.register(Walkman.TapeRegistry, pid, nil)
    {:reply, :ok, state}
  end

  def handle_call(:get_replay_mode, _from, %{replay_mode: replay_mode} = s) do
    {:reply, replay_mode, s}
  end

  def handle_call({:record, args, output}, _from, s) do
    {:reply, :ok, %{s | tests: [{args, output} | s.tests]}}
  end

  def handle_call({:replay, args}, _from, s) do
    case s.preserve_order do
      true ->
        # only match on first test, then discard it to preserve order
        case s.tests do
          [] ->
            {:reply, {:walkman_error, "there are no more calls left to replay"}, s}

          [{replay_args, value} | tests] ->
            if args_match?(replay_args, args) do
              {:reply, value, %{s | tests: tests}}
            else
              {:reply,
               {:walkman_error,
                "replay found #{inspect(replay_args)} didn't match given args #{inspect(args)}"},
               s}
            end
        end

      false ->
        Enum.find(s.tests, :module_test_not_found, fn
          {replay_args, _output} -> args_match?(replay_args, args)
        end)
        |> case do
          :module_test_not_found ->
            {:reply, {:walkman_error, "replay not found for args #{inspect(args)}"}, s}

          {_key, value} ->
            {:reply, value, s}
        end
    end
  end

  def handle_call(:finish, _from, %{replay_mode: :record} = s) do
    save_replay(s.tape_id, s.tests)
    {:stop, :normal, :ok, %{s | tests: [], replay_mode: nil}}
  end

  def handle_call(:finish, _from, s) do
    {:stop, :normal, :ok, %{s | tests: [], replay_mode: nil}}
  end

  def handle_call(:cancel, _from, s) do
    {:stop, :normal, :ok, %{s | tests: [], replay_mode: nil}}
  end

  defp filename(tape_id) do
    Path.relative_to("test/fixtures/walkman/#{tape_id}", File.cwd!())
  end

  defp load_replay(tape_id) do
    case File.read(filename(tape_id)) do
      {:ok, contents} -> {:ok, :erlang.binary_to_term(contents)}
      {:error, err} -> {:error, err}
    end
  end

  defp save_replay(tape_id, tests) do
    Path.relative_to("test/fixtures/walkman", File.cwd!()) |> File.mkdir_p()
    filename(tape_id) |> File.write!(:erlang.term_to_binary(Enum.reverse(tests)), [:write])
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
