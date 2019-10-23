# Walkman

[![Hex pm](http://img.shields.io/hexpm/v/walkman.svg?style=flat)](https://hex.pm/packages/walkman) [![CircleCI badge](https://circleci.com/gh/derekkraan/walkman.svg?style=svg&circle-token=:circle-token)](https://circleci.com/gh/derekkraan/walkman)

Walkman was inspired by Ruby's VCR. While VCR deals explicitely with HTTP requests, Walkman is useful for performing automated mocking of any module.

Walkman wraps modules instead of modifying them directly, which means there is less funny business going on, so less chance newer versions of Elixir will break the package. Walkman is more explicit and less magical, and as a result you will have to write a tiny bit more boilerplate than you're maybe used to.

## Getting started

Somewhere in your application you've got a module, `MyModule`, that communicates with the outside world. Perhaps it is an SSH driver, or it makes an HTTP request.

Make the location of this module configurable

```elixir
# config/config.exs

config :my_app, my_module: MyModule
```

```elixir
# config/test.exs

config :my_app, my_module: MyModuleWrapper
```

Replace `MyModule` in your application with `Application.get_env(:my_app, :my_module)`.

Wrap `MyModule` with `MyModuleWrapper`.

```elixir
# test/support/my_module_wrapper.ex

require Walkman

Walkman.def_stub(MyModuleWrapper, for: MyModule)
```

Lastly, in `mix.exs`, add `test/support/` to the paths that need to be compiled in `:test`.

```elixir
def project do
  [
    # Everything that usually goes here
    elixirc_paths: elixirc_paths(Mix.env())
  ]
end

defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

Now you can use "tapes" in your tests.

```elixir
test "MyModule" do
  Walkman.use_tape "my wrapper tape" do
    # test code that uses `MyModule` underwater
  end
end
```

Add the fixtures that Walkman creates to your repository.

## Generating fresh fixtures

To generate new fixtures, just remove the "tapes" you want to regenerate and re-run the tests. Like VCR, if Walkman doesn't find an existing fixture, it will create one.

## Fixture file format

Fixtures are saved in Erlang's binary [External Term Format](http://erlang.org/doc/apps/erts/erl_ext_dist.html), which most editors won't be able to open correctly. If you want to see what exactly has been recorded, you can use `:erlang.binary_to_term()` to parse the file contents back into readable Elixir terms.

```elixir
File.read!("path/to/fixture") |> :erlang.binary_to_term()
```

## Changing default tape mode

By default, all Walkman tapes are only available in the scope of the current process.
To make the tape available to other processes you have to set `global: true`:

```elixir
test "MyModule" do
  Walkman.use_tape "my wrapper tape", global: true do
    # test code that uses `MyModule` underwater
  end
end
```

The default behaviour can be changed in `config/test.exs`:

`config :walkman, global: true`

## Disabling module md5 checks

By default Walkman re-record tapes every time the wrapped module changes and this is done by storing the md5 of the module on the tape.

To change this behaviour the option `module_changes` should be set to `:ignore` or `:warn` which can be done per tape as in the example below:

```elixir
test "MyModule" do
  Walkman.use_tape "my wrapper tape", module_changes: :warn do
    # test code that uses `MyModule` underwater
  end
end
```

The module_changes option accepts the following values:
- `:rerecord` - if the recorded module changes the tape is automatically re-recorded.
- `:warn` - if the recorded module changes a warning is logged.
- `:ignore` - It ignores any changes in the recorded module

The default behaviour can also be changed in `config/test.exs`:

`config :walkman, module_changes: :ignore`

## Running "integration" specs

If you set Walkman to `:integration` mode then it will pass all function calls through to the wrapped module (instead of using the fixtures).

`Walkman.set_mode(:integration)`

## Limitations

o Walkman cannot run specs in parallel. Walkman sets the "tape" globally and would have no way of knowing from which test a particular call originates.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `walkman` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:walkman, "~> 0.3.0", only: :test}
  ]
end
```

## Contributing

Note that if you want to run Walkman's tests locally, you'll need to be running Elixir v1.9.1 and Erlang v22.1.
