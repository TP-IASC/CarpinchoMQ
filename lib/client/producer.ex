defmodule Producer do
  require OK
  def new_queue(queue_name, max_size, work_mode) do
    unless Enum.member?([:publish_subscribe, :work_queue], work_mode) do
      OK.failure(Errors.invalid_work_mode(work_mode))
    else
      Queue.new(queue_name, max_size, work_mode)
    end
  end

  def delete_queue(queue_name) do
    Queue.delete(queue_name)
  end

  def push_message(queue_name, message) do
    Queue.call(queue_name, {:push, message})
  end
end
