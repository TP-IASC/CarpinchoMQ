defmodule Consumer do
  use GenServer
  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call({:send_message, message, consumer_pid, queue_name}, _from, state) do
    :timer.sleep(:timer.seconds(20))
    Logger.info "Consumer \"#{inspect consumer_pid}\" received message: \"#{message.payload}\" from queue #{queue_name}"
    { :reply, :ack, state }
  end

  def subscribe(queue_name, pid) do
    Queue.call(queue_name, { :subscribe, pid })
  end

  def unsubscribe(queue_name, pid) do
    Queue.call(queue_name, { :unsubscribe, pid })
  end

  def send_message(consumer_pid, message, queue_name) do
    GenServer.call(consumer_pid, { :send_message, message, consumer_pid, queue_name })
  end
end
