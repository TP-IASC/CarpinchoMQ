defmodule Producer do
  require OK
  def new_queue(queue_name, max_size, work_mode, queue_mode) do
    Queue.new(queue_name, max_size, work_mode, queue_mode)
  end

  def delete_queue(queue_name) do
    Queue.delete(queue_name)
  end

  def push_message(queue_name, message) do
    Queue.call(queue_name, {:push, message})
  end
end
