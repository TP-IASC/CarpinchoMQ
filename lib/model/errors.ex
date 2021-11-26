defmodule Errors do
  def error(name, message) when is_atom(name),
    do: { :error, { name, message } }
end
