defmodule Walkman.Wrapper do
  @moduledoc """
  Use Walkman.Wrapper to isolate modules from the outside world.

  ```elixir
  defmodule MyModule do
    def my_function do
      # ...
    end

    # ...
  end

  defmodule MyModuleWrapper do
    use Walkman.Wrapper, MyModule
  end
  ```

  Now `MyModuleWrapper` can be used instead of `MyModule` to test your application.
  """

  defmacro __using__(module) do
    quote bind_quoted: [module: module] do
      Enum.each(module.__info__(:functions), fn {fun, arity} ->
        args = Macro.generate_arguments(arity, module)

        def unquote(fun)(unquote_splicing(args)) do
          Walkman.call_function(unquote(module), unquote(fun), unquote(args))
        end
      end)
    end
  end
end
