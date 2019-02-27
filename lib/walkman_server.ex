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
            raise "there are no more calls left to replay"

          [{replay_args, value} | tests] ->
            if replay_args == args do
              {:reply, value, %{s | tests: tests}}
            else
              raise "replay found #{inspect(replay_args)} didn't match given args #{inspect(args)}"
            end
        end

      false ->
        {_key, value} =
          Enum.find(s.tests, :module_test_not_found, fn
            {replay_args, _output} -> replay_args == args
          end)
          |> case do
            :module_test_not_found -> raise "replay not found for args #{inspect(args)}"
            other -> other
          end

        {:reply, value, s}
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
end
