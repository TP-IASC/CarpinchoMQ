defmodule Producer do
  def new_queue(queue_name, max_size, work_mode) do
    Queue.new(queue_name, max_size, work_mode)
  end

  def push_message(queue_name, message) do
    Queue.call(queue_name, {:push, message})
  end
end
