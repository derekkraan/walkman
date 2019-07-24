# Walkman

[![Hex pm](http://img.shields.io/hexpm/v/walkman.svg?style=flat)](https://hex.pm/packages/walkman) [![CircleCI badge](https://circleci.com/gh/derekkraan/walkman.png?circle-token=:circle-token)](https://circleci.com/gh/derekkraan/walkman)

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

defmodule MyModuleWrapper do
  use Walkman.Wrapper, MyModule
end
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

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/walkman](https://hexdocs.pm/walkman).
