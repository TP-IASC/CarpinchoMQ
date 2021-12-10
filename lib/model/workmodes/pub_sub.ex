defmodule PubSub do
  @behaviour WorkMode

  def to_atom, do: :pub_sub

  def push_message(queue_state, message) do
    Queue.cast(queue_state.name, {:send_to_subscribers, message})
  end

  def handle_timeout(queue_state, element) do
    Queue.warning(queue_state.name, "message timeout #{inspect(element.message)}, message discarded")
    Queue.cast(queue_state.name, {:delete, element})
    Queue.cast(queue_state.name, {:delete_dead_subscribers, element.consumers_that_did_not_ack})
  end
end
