defmodule WalkmanServer do
  use GenServer

  @moduledoc false

  defstruct mode: :mode_not_set, test_id: nil, tests: [], test_options: []

  def init(_nil) do
    {:ok, %__MODULE__{}}
  end

  def handle_call(:start, _from, %{mode: :normal} = s) do
    {:reply, :ok, %{s | tests: []}}
  end

  def handle_call(:start, _from, s) do
    case load_replay(s.test_id) do
      {:ok, tests} ->
        {:reply, :ok, %{s | mode: :replay, tests: tests}}

      {:error, _err} ->
        {:reply, :ok, %{s | mode: :record, tests: []}}
    end
  end

  def handle_call(:finish, _from, %{mode: :record} = s) do
    save_replay(s.test_id, s.tests)
    {:reply, :ok, %{s | tests: []}}
  end

  def handle_call(:finish, _from, s) do
    {:reply, :ok, %{s | tests: []}}
  end

  def handle_call({:record, args, output}, _from, s) do
    {:reply, :ok, %{s | tests: [{args, output} | s.tests]}}
  end

  def handle_call({:replay, args}, _from, s) do
    case Keyword.get(s.test_options, :preserve_order, false) do
      true ->
        # only match on first test, then discard it to preserve order
        case s.tests do
          [] ->
            {:reply, {:error, "there are no more calls left to replay"}, s}

          [{replay_args, value} | tests] ->
            if args_match?(replay_args, args) do
              {:reply, value, %{s | tests: tests}}
            else
              {:reply,
               {:error,
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
            {:reply, {:error, "replay not found for args #{inspect(args)}"}, s}

          {_key, value} ->
            {:reply, value, s}
        end
    end
  end

  def handle_call({:set_mode, mode}, _from, s)
      when mode in [:record, :replay, :normal] do
    {:reply, :ok, %{s | mode: mode, tests: []}}
  end

  def handle_call(:mode, _from, %{mode: mode} = s) do
    {:reply, mode, s}
  end

  def handle_call({:set_test_id, test_id, test_options}, _from, s) do
    {:reply, :ok, %{s | test_id: test_id, test_options: test_options, tests: []}}
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
    filename(test_id) |> File.write!(:erlang.term_to_binary(Enum.reverse(tests)), [:write])
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
