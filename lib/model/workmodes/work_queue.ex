defmodule WorkQueue do
  @behaviour WorkMode

  def to_atom, do: :work_queue

  def push_message(queue_state, message) do
    Queue.cast(queue_state.name, {:send_to_subscriber, message})
  end

  def handle_timeout(queue_state, element) do
    Queue.warning(queue_state.name, "message timeout #{inspect(element.message)}, retrying with the next subscriber")
    push_message(queue_state, element.message)
  end
end
