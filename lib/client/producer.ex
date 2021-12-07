defmodule Producer do
  require OK
  require Logger
  def new_queue(queue_name, max_size, work_mode, queue_mode) do
    Logger.info("Creating queue: #{queue_mode}")
    unless Enum.member?([:publish_subscribe, :work_queue], work_mode) and Enum.member?([:non_transactional, :transactional], queue_mode) do
      OK.failure(
        {
          :non_existent_work_mode,
          "Work mode \"#{work_mode}/\" or Queue mode \"#{
            queue_mode
          }/\" does not exist. Available work modes: :publish_subscribe and :work_queue. Available queue modes: :transactional and :non_transactional"
        }
      )
    else
      Logger.info("Entre")
      Queue.new(queue_name, max_size, work_mode, queue_mode)
    end
  end

  def delete_queue(queue_name) do
    Queue.delete(queue_name)
  end

  def push_message(queue_name, message) do
    Queue.call(queue_name, {:push, message})
  end
end
