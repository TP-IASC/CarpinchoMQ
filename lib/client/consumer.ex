defmodule Consumer do
  def ack(queue_name, message_id, consumer) do
    Queue.cast(queue_name, { :ack, message_id, consumer })
  end

  def subscribe(queue_name, consumer) do
    Queue.call(queue_name, { :subscribe, consumer })
  end

  def unsubscribe(queue_name, consumer) do
    Queue.call(queue_name, { :unsubscribe, consumer })
  end
end
