defmodule Producer do
  require OK
  def new_queue(queue_name, max_size, work_mode) do
    unless Enum.member?([:publish_subscribe, :work_queue], work_mode) do
      OK.failure({:non_existent_work_mode, "Work mode \"#{work_mode}\" does not exist. Available work modes: :publish_subscribe and :work_queue"})
    else
      Queue.new(queue_name, max_size, work_mode)
    end
  end

  def push_message(queue_name, message) do
    Queue.call(queue_name, {:push, message})
  end
end
