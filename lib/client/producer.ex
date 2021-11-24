defmodule Producer do
  def new_queue(queue_name, work_mode) do
    unless Enum.member?([:publish_subscribe, :work_queue], work_mode) do
      raise "Work mode \"#{work_mode}\" does not exist. Available work modes: :publish_subscribe and :work_queue"
    else
      Queue.new(queue_name, work_mode)
    end
  end

  def push_message(queue_name, message) do
    Queue.cast(queue_name, {:push, message})
  end
end
