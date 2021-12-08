defmodule WorkMode do
  @type t :: module()

  @callback to_atom :: atom()
  @callback push_message(queue_state :: Queue.t(), message :: any()) :: any()
  @callback handle_timeout(queue_state :: Queue.t(), element :: any()) :: any()
end
