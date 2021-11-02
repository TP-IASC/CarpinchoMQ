defmodule Producer do
  def new_queue(queue_name) do
    Queue.new(queue_name)
  end

  def push_message(queue_name, message) do
    Queue.cast(queue_name, {:push, message})
  end
end
