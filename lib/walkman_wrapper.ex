defmodule Walkman.Wrapper do
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
