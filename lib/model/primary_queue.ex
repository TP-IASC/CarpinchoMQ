defmodule PrimaryQueue do
  use Queue
  require Logger

  def init(default_state) do
    info(default_state.name, "queue started")
    Process.flag(:trap_exit, true)
    { :ok, default_state, { :continue, :check_replica } }
  end

  def handle_continue(:check_replica, default_state) do
    replica = Queue.replica_name(default_state.name)
    state = if Queue.alive?(replica) do
      debug(default_state.name, "restored from replica")
      Queue.state(replica) |> Map.put(:name, default_state.name)
    else
      default_state
    end

    { :noreply, state }
  end

  def handle_call({:push, payload}, _from, state) do
    size = Enum.count(state.elements)
    if size >= state.max_size do
      { :reply, OK.failure({:max_size_exceded, "queue max size (#{state.max_size}) cannot be exceded"}), state }
    else
      new_message = create_message(payload)

      send_to_replica(state.name, { :push, new_message })

      if state.work_mode == :publish_subscribe, do: Queue.cast(state.name, {:send_to_subscribers, new_message})

      { :reply, OK.success(:message_queued), Map.put(state, :elements, [%{message: new_message, consumers_that_did_not_ack: []}|state.elements]) }
    end
  end

  def handle_call({:subscribe, consumer}, _from, state) do
    if Enum.member?(state.subscribers, consumer) do
      { :reply, :already_subscribed, state }
    else
      send_to_replica(state.name, { :subscribe, consumer })
      debug(state.name, "subscribed #{inspect(consumer)}")
      { :reply, :subscribed, Map.put(state, :subscribers, [consumer|state.subscribers]) }
    end
  end

  def handle_call({:unsubscribe, consumer}, _from, state) do
    unless Enum.member?(state.subscribers, consumer) do
      { :reply, :not_subscribed, state }
    else
      send_to_replica(state.name, { :unsubscribe, consumer })
      debug(state.name, "unsubscribed #{inspect(consumer)}")
      { :reply, :unsubscribed, Map.put(state, :subscribers, List.delete(state.subscribers, consumer)) }
    end
  end

  def handle_cast({:ack, message_id, consumer}, state) do
    new_state = Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message.id == message_id do
        debug(state.name, "message #{message_id} acknowledged by #{inspect(consumer)}")
        Map.put(element, :consumers_that_did_not_ack, List.delete(element.consumers_that_did_not_ack, consumer))
      else
        element
      end
    end))

    elem = Enum.find(new_state.elements, fn element -> element.message.id == message_id end)
    if Enum.empty?(elem.consumers_that_did_not_ack) do
      Queue.cast(state.name, {:delete, elem})
    end

    send_to_replica(state.name, { :ack, message_id, consumer })
    { :noreply, new_state }
  end

  def handle_cast({:delete, elem}, state) do
    debug(state.name, "message #{inspect(elem.message)} deleted")
    send_to_replica(state.name, {:delete, elem})
    { :noreply, Map.put(state, :elements, List.delete(state.elements, elem)) }
  end

  def handle_cast({:send_to_subscribers, message}, state) do
    queue_name = state.name
    queue_subscribers = state.subscribers
    if Enum.empty?(queue_subscribers) do
      warning(queue_name, "not enough subscribers to send the message")
      { :noreply, state }
    else
      Enum.each(queue_subscribers, fn subscriber ->
        send_to_subscriber(queue_name, message, subscriber)
      end)
      { :noreply, add_receivers_to_state_message(state, queue_subscribers, message) }
    end
  end

  defp add_receivers_to_state_message(state, subscribers, message) do
    send_to_replica(state.name, { :add_receivers_to_state_message, subscribers, message })
    Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message == message do
        Map.put(element, :consumers_that_did_not_ack, subscribers)
      else
        element
      end
    end))
  end

  defp send_to_subscriber(queue_name, message, subscriber) do
    debug(queue_name, "message #{inspect(message)} sent to #{inspect(subscriber)}")
    GenServer.cast(UDPServer, { :send_message, queue_name, message, subscriber })
  end

  defp send_to_replica(queue_name, request) do
    Queue.replica_name(queue_name)
      |> Queue.cast(request)
  end
end
