defmodule WalkmanTest do
  use ExUnit.Case
  doctest Walkman
  require Walkman
  import ExUnit.CaptureLog

  test "without tape" do
    assert {:ok, "echo"} = TestEchoWrapper.echo("echo")
    assert_receive("echo", 10)
  end

  test "uses a pre-recorded tape" do
    Walkman.use_tape "echo" do
      assert {:ok, "echo"} = TestEchoWrapper.echo("echo")
      refute_receive("echo", 10)
    end
  end

  test "works in integration mode" do
    Walkman.set_mode(:integration)

    Walkman.use_tape "integration mode" do
      assert {:ok, "integration"} = TestEchoWrapper.echo("integration")
      assert_receive("integration", 10)
    end

    Walkman.set_mode(:normal)
  end

  test "records a fixture" do
    File.rm("test/fixtures/walkman/record a fixture")
    refute File.exists?("test/fixtures/walkman/record a fixture")

    Walkman.use_tape "record a fixture" do
      assert {:ok, "record a fixture"} = TestEchoWrapper.echo("record a fixture")
    end

    assert File.exists?("test/fixtures/walkman/record a fixture")
  end

  test "does not record a fixture when the test fails" do
    assert_raise(MatchError, fn ->
      Walkman.use_tape "no_fixture" do
        :does_not_match = TestEchoWrapper.echo("do not record this")
      end
    end)

    refute File.exists?("test/fixtures/walkman/no_fixture")
  end

  test "does not fail silently on RuntimeError" do
    assert_raise(RuntimeError, fn ->
      Walkman.use_tape "run_time_error" do
        raise "Error"
      end
    end)
  end

  test "can detect module md5 changes" do
    defmodule SomeModuleA do
      # The tape was recorded when some_function/0 was returning :ok.
      def some_function do
        :something
      end
    end

    Walkman.def_stub(SomeModuleWrapperA, for: SomeModuleA)

    assert capture_log([level: :info], fn ->
             try do
               Walkman.use_tape "check_module_changes_enabled", module_changes: :rerecord do
                 # The tape was recorded when some_function/0 was returning :ok.
                 refute :ok == SomeModuleWrapperA.some_function()
                 assert :something == SomeModuleWrapperA.some_function()
                 raise "Error to avoid the tape being re-recorded"
               end
             rescue
               e in RuntimeError -> e
             end
           end) =~ "[info]  Re-recording check_module_changes_enabled"
  end

  test "can disable module md5 checks" do
    defmodule SomeModuleB do
      def some_function do
        :something
      end
    end

    Walkman.def_stub(SomeModuleWrapperB, for: SomeModuleB)

    assert capture_log(fn ->
             Walkman.use_tape "check_module_changes_disabled", module_changes: :ignore do
               # The tape was recorded when some_function/0 was returning :ok.
               assert :ok == SomeModuleWrapperB.some_function()
             end
           end) == ""
  end

  test "warn when module md5 changes" do
    defmodule SomeModuleC do
      def some_function do
        :something
      end
    end

    Walkman.def_stub(SomeModuleWrapperC, for: SomeModuleC)

    assert capture_log([level: :warn], fn ->
             Walkman.use_tape "check_module_changes_warn", module_changes: :warn do
               # The tape was recorded when some_function/0 was returning :ok.
               assert :ok == SomeModuleWrapperC.some_function()
             end
           end) =~ "[warn]  Module Elixir.WalkmanTest.SomeModuleC has changed"
  end

  test "detects module md5 changes by default" do
    defmodule SomeModuleD do
      # The tape was recorded when some_function/0 was returning :ok.
      def some_function do
        :something
      end
    end

    Walkman.def_stub(SomeModuleWrapperD, for: SomeModuleD)

    assert capture_log([level: :info], fn ->
             try do
               Walkman.use_tape "check_module_changes_default" do
                 # The tape was recorded when some_function/0 was returning :ok.
                 refute :ok == SomeModuleWrapperD.some_function()
                 assert :something == SomeModuleWrapperD.some_function()
                 raise "Error to avoid the tape being re-recorded"
               end
             rescue
               e in RuntimeError -> e
             end
           end) =~ "[info]  Re-recording check_module_changes_default"
  end
end
