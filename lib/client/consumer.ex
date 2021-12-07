defmodule Consumer do
  use GenServer
  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:send_message, message, consumer_pid, queue_name}, state) do
    Logger.info "The consumer #{inspect consumer_pid} received the message: #{message.payload} from queue #{queue_name}"
#     :timer.sleep(:timer.seconds(60)) # Este sleep esta bueno para que el consumer tarde un tiempo en responder el ack, y poder ver el estado de la cola en el medio
    Queue.cast(queue_name, {:send_ack, message, consumer_pid})
    { :noreply, state }
  end

  def subscribe(queue_name, pid) do
    Queue.call(queue_name, { :subscribe, pid })
  end

  def unsubscribe(queue_name, pid) do
    Queue.call(queue_name, { :unsubscribe, pid })
  end

  def cast(consumer_pid, request) do
    GenServer.cast(consumer_pid, request)
  end
end
